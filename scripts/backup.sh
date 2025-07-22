#!/bin/bash

# =====================================================
# SCRIPT DE RESPALDO AUTOMÁTICO
# Sistema de Tickets IT - VENTURINO
# =====================================================

set -e

# Configuración
APP_DIR="/var/www/it-ticket-system"
BACKUP_DIR="/root/backups"
DB_NAME="venturino_tickets_db"
DB_USER="tickets_user"
RETENTION_DAYS=30
LOG_FILE="/var/log/backup.log"

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Función de logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "[ERROR] $1" >> $LOG_FILE
    exit 1
}

# Crear directorio de respaldos
mkdir -p $BACKUP_DIR

# Fecha para nombres de archivo
DATE=$(date +%Y%m%d_%H%M%S)

log "🔄 Iniciando respaldo automático"

# =====================================================
# RESPALDO DE BASE DE DATOS
# =====================================================

log "💾 Respaldando base de datos MySQL..."

DB_BACKUP_FILE="$BACKUP_DIR/db_backup_$DATE.sql"

# Leer contraseña del archivo .env si existe
if [ -f "$APP_DIR/.env" ]; then
    DB_PASS=$(grep "^DB_PASSWORD=" "$APP_DIR/.env" | cut -d'=' -f2)
    if [ ! -z "$DB_PASS" ]; then
        mysqldump -u $DB_USER -p$DB_PASS $DB_NAME > $DB_BACKUP_FILE
    else
        error "No se pudo obtener la contraseña de la base de datos"
    fi
else
    error "Archivo .env no encontrado"
fi

# Comprimir respaldo de BD
gzip $DB_BACKUP_FILE
log "✅ Base de datos respaldada: ${DB_BACKUP_FILE}.gz"

# =====================================================
# RESPALDO DE APLICACIÓN
# =====================================================

log "📁 Respaldando archivos de aplicación..."

APP_BACKUP_FILE="$BACKUP_DIR/app_backup_$DATE.tar.gz"

# Crear respaldo excluyendo node_modules y logs
tar -czf $APP_BACKUP_FILE \
    --exclude='node_modules' \
    --exclude='logs' \
    --exclude='.git' \
    --exclude='uploads/temp' \
    -C /var/www it-ticket-system

log "✅ Aplicación respaldada: $APP_BACKUP_FILE"

# =====================================================
# RESPALDO DE CONFIGURACIÓN DEL SISTEMA
# =====================================================

log "⚙️ Respaldando configuraciones del sistema..."

CONFIG_BACKUP_FILE="$BACKUP_DIR/config_backup_$DATE.tar.gz"

tar -czf $CONFIG_BACKUP_FILE \
    /etc/nginx/sites-available/ \
    /etc/mysql/mysql.conf.d/ \
    /etc/ssl/certs/ \
    /etc/letsencrypt/ \
    2>/dev/null || true

log "✅ Configuraciones respaldadas: $CONFIG_BACKUP_FILE"

# =====================================================
# VERIFICACIÓN DE RESPALDOS
# =====================================================

log "🔍 Verificando integridad de respaldos..."

# Verificar que los archivos existen y tienen tamaño > 0
for file in "${DB_BACKUP_FILE}.gz" "$APP_BACKUP_FILE" "$CONFIG_BACKUP_FILE"; do
    if [ -f "$file" ] && [ -s "$file" ]; then
        SIZE=$(du -h "$file" | cut -f1)
        log "✅ $file ($SIZE)"
    else
        error "Respaldo fallido o vacío: $file"
    fi
done

# =====================================================
# LIMPIEZA DE RESPALDOS ANTIGUOS
# =====================================================

log "🧹 Limpiando respaldos antiguos (>$RETENTION_DAYS días)..."

# Contar respaldos antes de limpiar
BEFORE_COUNT=$(find $BACKUP_DIR -name "*.gz" -o -name "*.tar.gz" | wc -l)

# Eliminar respaldos antiguos
find $BACKUP_DIR -name "db_backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete
find $BACKUP_DIR -name "app_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete
find $BACKUP_DIR -name "config_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete

# Contar respaldos después de limpiar
AFTER_COUNT=$(find $BACKUP_DIR -name "*.gz" -o -name "*.tar.gz" | wc -l)
DELETED_COUNT=$((BEFORE_COUNT - AFTER_COUNT))

if [ $DELETED_COUNT -gt 0 ]; then
    log "🗑️ Eliminados $DELETED_COUNT respaldos antiguos"
fi

# =====================================================
# ESTADÍSTICAS DE RESPALDOS
# =====================================================

log "📊 Estadísticas de respaldos:"

TOTAL_SIZE=$(du -sh $BACKUP_DIR | cut -f1)
TOTAL_FILES=$(find $BACKUP_DIR -type f | wc -l)

echo "   📁 Directorio: $BACKUP_DIR"
echo "   📦 Tamaño total: $TOTAL_SIZE"
echo "   📄 Total archivos: $TOTAL_FILES"
echo "   🕒 Retención: $RETENTION_DAYS días"

# Listar respaldos recientes
echo "   📋 Respaldos de hoy:"
find $BACKUP_DIR -name "*$(date +%Y%m%d)*" -type f -exec ls -lh {} \; | awk '{print "      " $9 " (" $5 ")"}'

# =====================================================
# NOTIFICACIÓN (OPCIONAL)
# =====================================================

# Si existe webhook de Slack/Discord, enviar notificación
if [ ! -z "$BACKUP_WEBHOOK" ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"✅ Respaldo completado - Sistema de Tickets IT\\nTamaño: $TOTAL_SIZE | Archivos: $TOTAL_FILES\"}" \
        $BACKUP_WEBHOOK 2>/dev/null || true
fi

# =====================================================
# PRUEBA DE RESTAURACIÓN (OPCIONAL)
# =====================================================

if [ "$1" = "--test-restore" ]; then
    log "🧪 Ejecutando prueba de restauración..."
    
    # Crear base de datos temporal para prueba
    TEST_DB="test_restore_$(date +%s)"
    mysql -u $DB_USER -p$DB_PASS -e "CREATE DATABASE $TEST_DB;"
    
    # Restaurar respaldo en BD temporal
    gunzip -c "${DB_BACKUP_FILE}.gz" | mysql -u $DB_USER -p$DB_PASS $TEST_DB
    
    # Verificar que las tablas existen
    TABLE_COUNT=$(mysql -u $DB_USER -p$DB_PASS $TEST_DB -e "SHOW TABLES;" | wc -l)
    
    if [ $TABLE_COUNT -gt 1 ]; then
        log "✅ Prueba de restauración exitosa ($((TABLE_COUNT-1)) tablas)"
    else
        error "❌ Prueba de restauración fallida"
    fi
    
    # Limpiar BD temporal
    mysql -u $DB_USER -p$DB_PASS -e "DROP DATABASE $TEST_DB;"
fi

log "🎉 Respaldo completado exitosamente"

# =====================================================
# SALIDA FINAL
# =====================================================

echo
echo "=================================================="
echo "           RESUMEN DEL RESPALDO"
echo "=================================================="
echo "📅 Fecha: $(date)"
echo "💾 Base de datos: ${DB_BACKUP_FILE}.gz"
echo "📁 Aplicación: $APP_BACKUP_FILE"
echo "⚙️ Configuración: $CONFIG_BACKUP_FILE"
echo "📊 Tamaño total: $TOTAL_SIZE"
echo "🗂️ Total archivos: $TOTAL_FILES"
echo "=================================================="

exit 0
