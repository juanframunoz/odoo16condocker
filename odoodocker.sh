#!/usr/bin/env bash
#
# Script para:
#   1. Instalar Docker y Docker Compose (Ubuntu/Debian).
#   2. Configurar la localización en español (es_ES.UTF-8).
#   3. Desplegar Odoo en Docker con Traefik y Let's Encrypt (HTTPS).
#
# Uso:
#   chmod +x instalar_odoo_con_letsencrypt.sh
#   ./instalar_odoo_con_letsencrypt.sh
#

# ---------------------------------------------------------------------------
# 0. Configurar localización a español (es_ES.UTF-8)
# ---------------------------------------------------------------------------
echo "===================================================="
echo " [0/5] Configurando localización en español (es_ES) "
echo "===================================================="

# Instalar paquetes de localización
sudo apt-get update -y
sudo apt-get install locales -y

# Generar localización española
sudo locale-gen es_ES.UTF-8

# Actualizar las variables de entorno
sudo update-locale LANG=es_ES.UTF-8 LC_ALL=es_ES.UTF-8

# Exportar las variables para la sesión actual
export LANG=es_ES.UTF-8
export LANGUAGE=es_ES:en
export LC_ALL=es_ES.UTF-8

echo "Localización configurada: es_ES.UTF-8"
echo ""

# ---------------------------------------------------------------------------
# 1. Instalar Docker (Ubuntu/Debian)
# ---------------------------------------------------------------------------
echo "===================================================="
echo "  [1/5] Instalando Docker en el sistema...          "
echo "===================================================="

# Eliminar versiones previas de Docker (si existieran)
sudo apt-get remove docker docker-engine docker.io containerd runc -y

# Instalar paquetes necesarios
sudo apt-get update -y
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release -y

# Agregar la llave GPG oficial de Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor \
  -o /usr/share/keyrings/docker-archive-keyring.gpg

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
echo ""

# ---------------------------------------------------------------------------
# 2. Instalar Docker Compose (última versión estable)
# ---------------------------------------------------------------------------
echo "===================================================="
echo "  [2/5] Instalando Docker Compose...                "
echo "===================================================="

# Obtener la última versión de Docker Compose desde GitHub
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
  | grep tag_name | cut -d '"' -f 4)

# Descargar la versión específica para la arquitectura del sistema
sudo curl -L \
  "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose

# Dar permisos de ejecución
sudo chmod +x /usr/local/bin/docker-compose

# Crear enlace simbólico (opcional, por compatibilidad)
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true

echo "Docker Compose instalado correctamente (versión: ${DOCKER_COMPOSE_VERSION})."
echo ""

# ---------------------------------------------------------------------------
# 3. Solicitar dominio y correo para Let's Encrypt
# ---------------------------------------------------------------------------
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
      - "--entrypoints.web.address=:80"          # Entrada HTTP (necesaria para el desafío ACME)
      - "--entrypoints.websecure.address=:443"   # Entrada HTTPS
      - "--providers.docker=true"                # Detección de contenedores Docker
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
      # Ajustamos variables de entorno para localización en español dentro del contenedor
      - LANG=es_ES.UTF-8
      - LANGUAGE=es_ES:en
      - LC_ALL=es_ES.UTF-8
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
echo ""

# ---------------------------------------------------------------------------
# 5. Levantar los contenedores
# ---------------------------------------------------------------------------
echo "===================================================="
echo "  [5/5] Iniciando contenedores con Docker Compose... "
echo "===================================================="
docker-compose up -d

echo ""
echo "========================================================="
echo "        Odoo + PostgreSQL + Traefik (Let's Encrypt)      "
echo "          con localización española (es_ES.UTF-8)        "
echo "========================================================="
echo " Se han instalado Docker y Docker Compose correctamente."
echo " Se ha configurado el sistema en español (es_ES.UTF-8). "
echo " Se han levantado los contenedores en segundo plano.    "
echo "                                                       "
echo "  - Dominio: $DOMAIN                                   "
echo "                                                       "
echo " Inicialmente Odoo estará en http://$DOMAIN            "
echo " En unos minutos, se generará y activará el certificado"
echo " SSL, y podrás acceder vía https://$DOMAIN             "
echo "                                                       "
echo "---------------------------------------------------------"
echo " Para mayor seguridad, deshabilita '--api.insecure=true'"
echo " en la configuración de Traefik y protege su dashboard. "
echo "========================================================="
