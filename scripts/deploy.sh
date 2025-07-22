#!/bin/bash

# =====================================================
# SCRIPT DE DESPLIEGUE AUTOMÁTICO
# Sistema de Tickets IT - VENTURINO
# =====================================================

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
APP_NAME="tickets-system"
APP_DIR="/var/www/it-ticket-system"
BACKUP_DIR="/root/backups"
LOG_FILE="/var/log/deploy.log"

# Función para logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "[ERROR] $1" >> $LOG_FILE
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
    echo "[WARNING] $1" >> $LOG_FILE
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
    echo "[INFO] $1" >> $LOG_FILE
}

# Verificar que se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    error "Este script debe ejecutarse como root (sudo)"
fi

log "🚀 Iniciando despliegue del Sistema de Tickets IT"

# =====================================================
# FASE 1: PREPARACIÓN
# =====================================================

log "📋 FASE 1: Preparación del despliegue"

# Crear directorios necesarios
mkdir -p $BACKUP_DIR
mkdir -p /var/log
mkdir -p $APP_DIR/logs

# Verificar servicios críticos
info "Verificando servicios críticos..."

if ! systemctl is-active --quiet mysql; then
    error "MySQL no está ejecutándose"
fi

if ! systemctl is-active --quiet nginx; then
    error "Nginx no está ejecutándose"
fi

log "✅ Servicios críticos verificados"

# =====================================================
# FASE 2: RESPALDO
# =====================================================

log "💾 FASE 2: Creando respaldo de seguridad"

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/pre_deploy_backup_$BACKUP_DATE"

# Respaldo de base de datos
info "Respaldando base de datos..."
if [ -f /root/.my.cnf ]; then
    mysqldump venturino_tickets_db > "$BACKUP_FILE.sql"
else
    read -s -p "Ingresa la contraseña de MySQL: " MYSQL_PASS
    echo
    mysqldump -u tickets_user -p$MYSQL_PASS venturino_tickets_db > "$BACKUP_FILE.sql"
fi

# Respaldo de aplicación
info "Respaldando aplicación actual..."
if [ -d "$APP_DIR" ]; then
    tar -czf "$BACKUP_FILE.tar.gz" -C /var/www it-ticket-system
fi

log "✅ Respaldos creados: $BACKUP_FILE.*"

# =====================================================
# FASE 3: ACTUALIZACIÓN DE CÓDIGO
# =====================================================

log "📥 FASE 3: Actualizando código fuente"

cd $APP_DIR

# Verificar si es un repositorio Git
if [ -d ".git" ]; then
    info "Actualizando desde repositorio Git..."
    git fetch origin
    git pull origin main
else
    warning "No es un repositorio Git. Asegúrate de subir los archivos manualmente."
fi

# Instalar/actualizar dependencias
info "Instalando dependencias..."
npm install --production

log "✅ Código actualizado"

# =====================================================
# FASE 4: CONFIGURACIÓN
# =====================================================

log "⚙️ FASE 4: Verificando configuración"

# Verificar archivo .env
if [ ! -f "$APP_DIR/.env" ]; then
    warning "Archivo .env no encontrado. Copiando desde .env.example..."
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
    error "IMPORTANTE: Debes configurar el archivo .env antes de continuar"
fi

# Verificar permisos
chown -R www-data:www-data $APP_DIR
chmod -R 755 $APP_DIR
chmod 600 $APP_DIR/.env

# Crear directorio de uploads si no existe
mkdir -p $APP_DIR/uploads
chown -R www-data:www-data $APP_DIR/uploads

log "✅ Configuración verificada"

# =====================================================
# FASE 5: BASE DE DATOS
# =====================================================

log "🗄️ FASE 5: Actualizando base de datos"

# Verificar conexión a base de datos
info "Verificando conexión a base de datos..."
cd $APP_DIR
node -e "
const db = require('./server/config/database');
db.testConnection().then(success => {
    if (success) {
        console.log('Conexión exitosa');
        process.exit(0);
    } else {
        console.log('Error de conexión');
        process.exit(1);
    }
}).catch(() => process.exit(1));
" || error "No se puede conectar a la base de datos"

log "✅ Base de datos verificada"

# =====================================================
# FASE 6: REINICIO DE SERVICIOS
# =====================================================

log "🔄 FASE 6: Reiniciando servicios"

# Detener aplicación
info "Deteniendo aplicación..."
pm2 stop $APP_NAME 2>/dev/null || true

# Reiniciar aplicación
info "Iniciando aplicación..."
cd $APP_DIR
pm2 start server/server.js --name $APP_NAME --max-memory-restart 500M

# Guardar configuración PM2
pm2 save

# Verificar que la aplicación esté ejecutándose
sleep 5
if pm2 list | grep -q "$APP_NAME.*online"; then
    log "✅ Aplicación iniciada correctamente"
else
    error "La aplicación no pudo iniciarse"
fi

# Reiniciar Nginx
info "Reiniciando Nginx..."
nginx -t || error "Configuración de Nginx inválida"
systemctl reload nginx

log "✅ Servicios reiniciados"

# =====================================================
# FASE 7: VERIFICACIÓN
# =====================================================

log "🔍 FASE 7: Verificación del despliegue"

# Verificar que el sitio responda
info "Verificando respuesta del sitio..."
sleep 10

# Obtener dominio del archivo .env
DOMAIN=$(grep "^DOMAIN=" $APP_DIR/.env | cut -d'=' -f2)
if [ -z "$DOMAIN" ]; then
    DOMAIN="http://localhost:3000"
fi

# Verificar respuesta HTTP
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $DOMAIN || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    log "✅ Sitio web respondiendo correctamente ($HTTP_STATUS)"
else
    warning "El sitio web no responde correctamente (HTTP $HTTP_STATUS)"
    info "Verificando logs de la aplicación..."
    pm2 logs $APP_NAME --lines 10
fi

# Verificar logs de errores
if [ -f "$APP_DIR/logs/error.log" ]; then
    ERROR_COUNT=$(tail -100 "$APP_DIR/logs/error.log" | wc -l)
    if [ "$ERROR_COUNT" -gt 0 ]; then
        warning "Se encontraron $ERROR_COUNT errores recientes en los logs"
    fi
fi

# =====================================================
# FASE 8: LIMPIEZA
# =====================================================

log "🧹 FASE 8: Limpieza post-despliegue"

# Limpiar respaldos antiguos (mantener últimos 7 días)
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete 2>/dev/null || true
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete 2>/dev/null || true

# Limpiar logs antiguos
find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null || true

# Limpiar cache de npm
npm cache clean --force 2>/dev/null || true

log "✅ Limpieza completada"

# =====================================================
# RESUMEN FINAL
# =====================================================

log "🎉 DESPLIEGUE COMPLETADO EXITOSAMENTE"

echo
echo "=================================================="
echo "           RESUMEN DEL DESPLIEGUE"
echo "=================================================="
echo "📅 Fecha: $(date)"
echo "🏷️  Versión: $(cd $APP_DIR && git rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
echo "🌐 URL: $DOMAIN"
echo "💾 Respaldo: $BACKUP_FILE.*"
echo "📊 Estado PM2:"
pm2 list | grep $APP_NAME
echo "=================================================="
echo

info "Para verificar logs en tiempo real: pm2 logs $APP_NAME"
info "Para reiniciar la aplicación: pm2 restart $APP_NAME"
info "Para ver el estado: pm2 status"

log "✅ Despliegue finalizado correctamente"

# Enviar notificación (opcional)
if [ ! -z "$SLACK_WEBHOOK" ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"🚀 Despliegue completado: Sistema de Tickets IT - $(date)\"}" \
        $SLACK_WEBHOOK 2>/dev/null || true
fi

exit 0
