#!/bin/bash

# Formulario inicial para configurar dominio y correo de gestión
read -p "Introduce el dominio para acceder a Odoo (ejemplo: odoo.midominio.com): " DOMAIN
read -p "Introduce tu correo electrónico para la gestión de Let's Encrypt: " EMAIL

# Nombre del proyecto y directorio de trabajo
PROJECT_NAME="odoo17_ce_es"
PROJECT_DIR="$HOME/$PROJECT_NAME"

# Actualizar sistema e instalar dependencias necesarias
echo "Actualizando el sistema e instalando dependencias..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common git ufw

# Instalar Docker
echo "Instalando Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Habilitar y arrancar Docker
echo "Habilitando y arrancando Docker..."
sudo systemctl enable docker
sudo systemctl start docker

# Instalar Docker Compose
echo "Instalando Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/download/v2.22.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verificar instalación de Docker y Docker Compose
echo "Verificando Docker y Docker Compose..."
docker --version
docker-compose --version

# Configurar firewall y abrir puertos necesarios
echo "Configurando firewall y abriendo puertos 80 y 443..."
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Crear directorio del proyecto
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Crear archivo docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  odoo:
    image: odoo:17.0
    container_name: odoo17_ce
    depends_on:
      - db
    ports:
      - "8069:8069"
    volumes:
      - ./odoo-web-data:/var/lib/odoo
      - ./addons:/mnt/extra-addons
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo

  db:
    image: postgres:15
    container_name: odoo17_db
    environment:
      POSTGRES_DB=postgres
      POSTGRES_USER=odoo
      POSTGRES_PASSWORD=odoo
    volumes:
      - ./db-data:/var/lib/postgresql/data

  nginx:
    image: nginx:latest
    container_name: odoo17_nginx
    depends_on:
      - odoo
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx-conf:/etc/nginx/conf.d
      - ./certbot-etc:/etc/letsencrypt
      - ./certbot-var:/var/lib/letsencrypt

  certbot:
    image: certbot/certbot
    container_name: odoo17_certbot
    volumes:
      - ./certbot-etc:/etc/letsencrypt
      - ./certbot-var:/var/lib/letsencrypt
      - ./nginx-conf:/etc/nginx/conf.d
    entrypoint: ["/bin/sh", "-c"]
    command: "trap exit TERM; while :; do sleep 1 & wait $${!}; done"

volumes:
  odoo-web-data:
  addons:
  db-data:
  nginx-conf:
  certbot-etc:
  certbot-var:
EOF

# Crear directorios para los datos persistentes
mkdir -p odoo-web-data addons db-data nginx-conf certbot-etc certbot-var

# Crear configuración inicial de Nginx
cat <<EOF > nginx-conf/odoo.conf
server {
    server_name $DOMAIN;

    location / {
        proxy_pass http://odoo:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem; # managed by Certbot
}

server {
    if (\$host = $DOMAIN) {
        return 301 https://\$host\$request_uri;
    }

    listen 80;
    server_name $DOMAIN;
    return 404; # managed by Certbot
}
EOF

# Descargar localización española desde Odoo GitHub
echo "Descargando localización española..."
git clone --depth=1 https://github.com/OCA/l10n-spain addons/l10n_spain
rm -rf addons/l10n_spain/.git

# Opcional: Descargar módulos adicionales (ajustar según necesidad)
echo "Descargando módulos adicionales opcionales..."
# Ejemplo: git clone --depth=1 https://github.com/OCA/account-financial-tools addons/account_financial_tools

# Solicitar certificados SSL con Certbot
echo "Solicitando certificados SSL para $DOMAIN..."
docker-compose run certbot certonly --webroot --webroot-path=/var/lib/letsencrypt --email $EMAIL --agree-tos --no-eff-email -d $DOMAIN

# Iniciar los servicios con Docker Compose
echo "Iniciando servicios de Docker..."
docker-compose up -d

# Mensaje final
echo "
¡Instalación completada! 
Accede a Odoo en https://$DOMAIN 
Usuario predeterminado: admin 
Contraseña: admin (debes configurarla al iniciar sesión por primera vez)
"
