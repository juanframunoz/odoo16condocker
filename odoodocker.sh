#!/usr/bin/env bash
#
# Script para instalar Docker, Docker Compose y desplegar Odoo con Traefik (Let's Encrypt).
#
# Uso:
#   chmod +x instalar_odoo_con_letsencrypt.sh
#   ./instalar_odoo_con_letsencrypt.sh
#
# Probado en Ubuntu/Debian. Para otras distribuciones, ajusta los comandos de instalación.
#

# ---------------------------------------------------------------------------
# 1. Instalar Docker (Ubuntu/Debian)
# ---------------------------------------------------------------------------
echo "===================================================="
echo "  [1/5] Instalando Docker en el sistema...          "
echo "===================================================="

# Actualizar repositorios
sudo apt-get update -y

# Instalar paquetes necesarios
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release -y

# Eliminar versiones previas de Docker (si existieran)
sudo apt-get remove docker docker-engine docker.io containerd runc -y

# Agregar la llave GPG oficial de Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Agregar el repositorio estable de Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Actualizar repositorios e instalar Docker Engine
sudo apt-get update -y
sudo apt-get install docker-ce docker-ce-cli containerd.io -y

# Habilitar e iniciar Docker
sudo systemctl enable docker
sudo systemctl start docker

echo "Docker instalado correctamente."

# ---------------------------------------------------------------------------
# 2. Instalar Docker Compose (última versión estable)
# ---------------------------------------------------------------------------
echo ""
echo "===================================================="
echo "  [2/5] Instalando Docker Compose...                "
echo "===================================================="

# Descarga la versión estable (ajusta la versión si lo deseas)
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)

sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose

# Dar permisos de ejecución
sudo chmod +x /usr/local/bin/docker-compose

# Crear enlace simbólico (opcional, por compatibilidad)
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true

echo "Docker Compose instalado correctamente (versión: ${DOCKER_COMPOSE_VERSION})."

# ---------------------------------------------------------------------------
# 3. Solicitar dominio y correo para Let's Encrypt
# ---------------------------------------------------------------------------
echo ""
echo "===================================================="
echo "  [3/5] Configuración inicial: dominio y correo     "
echo "===================================================="
read -rp "Por favor ingresa el dominio (ej: odoo.midominio.com): " DOMAIN
read -rp "Por favor ingresa tu correo (para Let's Encrypt): " EMAIL

echo ""
echo "-----------------------------------------------------"
echo "Dominio : $DOMAIN"
echo "Correo  : $EMAIL"
echo "-----------------------------------------------------"
echo "Si los datos son correctos, presiona [Enter] para continuar."
echo "Si no, presiona CTRL + C para cancelar y vuelve a ejecutar."
read -r

# ---------------------------------------------------------------------------
# 4. Generar archivo docker-compose.yml
# ---------------------------------------------------------------------------
echo ""
echo "===================================================="
echo "  [4/5] Creando archivo docker-compose.yml          "
echo "===================================================="

cat <<EOF > docker-compose.yml
version: '3.3'

services:
  # Traefik actuará como proxy inverso y gestionará certificados SSL (Let's Encrypt).
  reverse-proxy:
    image: traefik:v2.9
    container_name: traefik
    command:
      - "--api.dashboard=true"                   # Habilita el dashboard de Traefik (opcional)
      - "--api.insecure=true"                    # Permite acceder al dashboard sin HTTPS (solo en entorno seguro)
      - "--entrypoints.web.address=:80"          # Entrada para HTTP (necesaria para el desafío ACME)
      - "--entrypoints.websecure.address=:443"   # Entrada para HTTPS
      - "--providers.docker=true"                # Habilita la detección de contenedores Docker
      - "--providers.docker.exposedbydefault=false"
      - "--certificatesresolvers.myresolver.acme.email=${EMAIL}"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.myresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.myresolver.acme.httpchallenge.entrypoint=web"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - traefik-certificates:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - web
    restart: unless-stopped

  # Contenedor PostgreSQL para la base de datos de Odoo
  db:
    image: postgres:13
    container_name: postgres_odoo
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - db-data:/var/lib/postgresql/data
    networks:
      - odoo_net
    restart: unless-stopped

  # Contenedor de Odoo
  odoo:
    image: odoo:16
    container_name: odoo
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo
    networks:
      - odoo_net
      - web
    depends_on:
      - db
    volumes:
      - odoo-addons:/mnt/extra-addons
    restart: unless-stopped
    labels:
      # Habilitar este servicio en Traefik
      - "traefik.enable=true"
      # Definir la regla para que se asocie a tu dominio
      - "traefik.http.routers.odoo.rule=Host(\`${DOMAIN}\`)"
      # Usar la entrada websecure de Traefik (puerto 443)
      - "traefik.http.routers.odoo.entrypoints=websecure"
      # Activar TLS y usar el resolver para Let's Encrypt
      - "traefik.http.routers.odoo.tls.certresolver=myresolver"
      # Definir el puerto interno donde escucha Odoo (8069)
      - "traefik.http.services.odoo.loadbalancer.server.port=8069"

volumes:
  traefik-certificates:
  db-data:
  odoo-addons:

networks:
  web:
    external: false
  odoo_net:
    external: false
EOF

echo "Archivo docker-compose.yml creado."

# ---------------------------------------------------------------------------
# 5. Levantar los contenedores
# ---------------------------------------------------------------------------
echo ""
echo "===================================================="
echo "  [5/5] Iniciando contenedores con Docker Compose... "
echo "===================================================="
docker-compose up -d

echo ""
echo "========================================================="
echo "        Odoo + PostgreSQL + Traefik (Let's Encrypt)      "
echo "========================================================="
echo " Se han instalado Docker y Docker Compose correctamente."
echo " Se han levantado los contenedores en segundo plano.   "
echo "                                                       "
echo "  - Dominio: $DOMAIN                                   "
echo "  - Dashboard Traefik: http://$DOMAIN:8080 (si abres el puerto y ajustas config) "
echo "                                                       "
echo " Inicialmente Odoo estará en http://$DOMAIN            "
echo " En unos minutos, se generará y activará el certificado"
echo " SSL, y podrás acceder vía https://$DOMAIN             "
echo "========================================================="
