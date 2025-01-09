#!/usr/bin/env bash
#
# Script para:
#   1. Instalar Docker y Docker Compose (Ubuntu/Debian).
#   2. Configurar la localización del sistema en español (es_ES.UTF-8).
#   3. Desplegar Odoo Community (16) en Docker con Traefik y Let's Encrypt (HTTPS).
#   4. Eliminar posibles módulos Enterprise.
#   5. Descargar e instalar la localización española de OCA (l10n-spain).
#
# Uso:
#   chmod +x instalar_odoo_con_letsencrypt.sh
#   ./instalar_odoo_con_letsencrypt.sh
#

# ---------------------------------------------------------------------------
# 0. Configurar localización a español (es_ES.UTF-8)
# ---------------------------------------------------------------------------
echo "===================================================="
echo " [0/9] Configurando localización en español (es_ES) "
echo "===================================================="

sudo apt-get update -y
sudo apt-get install locales -y

# Generar localización española
sudo locale-gen es_ES.UTF-8

# Actualizar variables de entorno del sistema
sudo update-locale LANG=es_ES.UTF-8 LC_ALL=es_ES.UTF-8

# Exportar para la sesión actual
export LANG=es_ES.UTF-8
export LANGUAGE=es_ES:en
export LC_ALL=es_ES.UTF-8

echo "Localización configurada: es_ES.UTF-8"
echo ""

# ---------------------------------------------------------------------------
# 1. Instalar Docker (Ubuntu/Debian)
# ---------------------------------------------------------------------------
echo "===================================================="
echo " [1/9] Instalando Docker en el sistema...           "
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
echo " [2/9] Instalando Docker Compose...                 "
echo "===================================================="

DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
  | grep tag_name | cut -d '"' -f 4)

# Descargar la versión específica para la arquitectura del sistema
sudo curl -L \
  "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose

# Dar permisos de ejecución
sudo chmod +x /usr/local/bin/docker-compose

# Crear enlace simbólico por compatibilidad
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true

echo "Docker Compose instalado correctamente (versión: ${DOCKER_COMPOSE_VERSION})."
echo ""

# ---------------------------------------------------------------------------
# 3. Solicitar dominio y correo para Let's Encrypt
# ---------------------------------------------------------------------------
echo "===================================================="
echo " [3/9] Configuración inicial: dominio y correo      "
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
# 4. Clonar la localización española de OCA (ramas 16.0)
# ---------------------------------------------------------------------------
echo ""
echo "===================================================="
echo " [4/9] Clonando localización española de OCA        "
echo "      (l10n-spain, rama 16.0)                       "
echo "===================================================="

# Creamos un directorio local para los módulos OCA
mkdir -p ./oca_l10n_spain

# Instalar git si no está instalado
sudo apt-get install -y git

# Clonar repositorio l10n-spain en la carpeta local (rama 16.0)
if [ -d "./oca_l10n_spain/.git" ]; then
  echo "Ya existe un repositorio en ./oca_l10n_spain. Actualizando..."
  cd ./oca_l10n_spain || exit
  git pull
  cd ..
else
  echo "Clonando repositorio OCA/l10n-spain (rama 16.0)"
  git clone -b 16.0 --depth=1 https://github.com/OCA/l10n-spain.git ./oca_l10n_spain
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Generar archivo docker-compose.yml
# ---------------------------------------------------------------------------
echo "===================================================="
echo " [5/9] Creando archivo docker-compose.yml           "
echo "===================================================="

cat <<EOF > docker-compose.yml
version: '3.3'

services:
  # Traefik: proxy inverso con Let’s Encrypt
  reverse-proxy:
    image: traefik:v2.9
    container_name: traefik
    command:
      - "--api.dashboard=true"                   # Dashboard de Traefik (opcional)
      - "--api.insecure=true"                    # Dashboard sin HTTPS (no recomendado en prod)
      - "--entrypoints.web.address=:80"          # HTTP (necesario para ACME)
      - "--entrypoints.websecure.address=:443"   # HTTPS
      - "--providers.docker=true"                # Auto-detección de servicios Docker
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

  # PostgreSQL
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

  # Odoo Community 16
  odoo:
    image: odoo:16
    container_name: odoo
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo
      # Ajustamos para localización en es_ES
      - LANG=es_ES.UTF-8
      - LANGUAGE=es_ES:en
      - LC_ALL=es_ES.UTF-8
    networks:
      - odoo_net
      - web
    depends_on:
      - db
    volumes:
      # Volumen persistente de addons
      - odoo-addons:/mnt/extra-addons
      # Montamos la carpeta local con los módulos OCA de España
      - ./oca_l10n_spain:/mnt/extra-addons/l10n-spain
    restart: unless-stopped
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.odoo.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.odoo.entrypoints=websecure"
      - "traefik.http.routers.odoo.tls.certresolver=myresolver"
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
# 6. Levantar contenedores
# ---------------------------------------------------------------------------
echo "===================================================="
echo " [6/9] Iniciando contenedores con Docker Compose... "
echo "===================================================="
docker-compose up -d

# ---------------------------------------------------------------------------
# 7. Eliminar módulos Enterprise (si existen) en Odoo
# ---------------------------------------------------------------------------
echo ""
echo "===================================================="
echo " [7/9] Eliminando posibles módulos Enterprise...    "
echo "===================================================="
sleep 5  # Espera unos segundos a que Odoo arranque
docker-compose exec odoo bash -c 'rm -rf /usr/lib/python3/dist-packages/odoo/addons/*enterprise* || true'
echo "Módulos Enterprise eliminados (si había)."
echo ""

# ---------------------------------------------------------------------------
# 8. Instalar módulos de localización española (OCA l10n-spain)
# ---------------------------------------------------------------------------
echo "===================================================="
echo " [8/9] Instalar módulos de localización española    "
echo "      (OCA: l10n_es, l10n_es_aeat, etc.)            "
echo "===================================================="

# Aquí defines los módulos que quieras instalar de la OCA.
# Añade, quita o ajusta según tus necesidades.
# Ejemplo de módulos OCA populares:
#   - l10n_es: localización base de España
#   - l10n_es_aeat: modelo de impuestos AEAT
#   - l10n_es_iban: validación de IBAN para España
#   - l10n_es_partner: DNI/NIF, checks, etc.
#   - l10n_es_toponyms: topónimos, poblaciones
#   - l10n_es_account_asset: gestión de activos
#   - l10n_es_aeat_mod111, l10n_es_aeat_mod303, l10n_es_aeat_mod347, l10n_es_aeat_sii, etc.

MODULES="l10n_es,l10n_es_aeat,l10n_es_iban,l10n_es_partner,l10n_es_toponyms"

# Instalamos los módulos en la base de datos "postgres"
docker-compose exec odoo bash -c "odoo -d postgres --stop-after-init -i ${MODULES}"

# Opcional: actualizamos todo con -u all (solo si deseas forzar la actualización de todos los módulos instalados)
# docker-compose exec odoo bash -c "odoo -d postgres --stop-after-init -u all"

echo "Localización española (OCA) instalada: ${MODULES}"
echo ""

# ---------------------------------------------------------------------------
# 9. Reiniciar Odoo para cargar correctamente los módulos
# ---------------------------------------------------------------------------
echo "===================================================="
echo " [9/9] Reiniciando Odoo para activar cambios...     "
echo "===================================================="

docker-compose restart odoo

echo ""
echo "==========================================================="
echo " Odoo Community + PostgreSQL + Traefik (Let's Encrypt)     "
echo "   con localización OCA l10n-spain y sin módulos Enterprise "
echo "==========================================================="
echo " Se han instalado Docker y Docker Compose correctamente."
echo " Se ha configurado el sistema en español (es_ES.UTF-8). "
echo " Se han levantado los contenedores en segundo plano.    "
echo "                                                       "
echo "  - Dominio: $DOMAIN                                   "
echo "                                                       "
echo " Inicialmente Odoo estará en http://$DOMAIN            "
echo " En unos minutos, Let’s Encrypt generará el certificado"
echo " SSL y podrás acceder vía https://$DOMAIN              "
echo "                                                       "
echo " Módulos instalados de OCA l10n-spain:                 "
echo "   ${MODULES}                                          "
echo "                                                       "
echo "---------------------------------------------------------"
echo " Para seguridad, deshabilita '--api.insecure=true'      "
echo " en la config de Traefik y protege su dashboard.        "
echo "==========================================================="
