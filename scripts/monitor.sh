#!/bin/bash

# =====================================================
# SCRIPT DE MONITOREO DEL SISTEMA
# Sistema de Tickets IT - VENTURINO
# =====================================================

# Configuración
APP_NAME="tickets-system"
APP_DIR="/var/www/it-ticket-system"
LOG_FILE="/var/log/monitor.log"
ALERT_EMAIL="admin@venturino.com.ar"
WEBHOOK_URL=""  # Slack/Discord webhook (opcional)

# Umbrales de alerta
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=85
RESPONSE_TIME_THRESHOLD=5000  # milisegundos

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Función de logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
    echo "[WARNING] $1" >> $LOG_FILE
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "[ERROR] $1" >> $LOG_FILE
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
    echo "[INFO] $1" >> $LOG_FILE
}

# Función para enviar alertas
send_alert() {
    local message="$1"
    local severity="$2"
    
    # Log local
    if [ "$severity" = "critical" ]; then
        error "$message"
    else
        warning "$message"
    fi
    
    # Enviar por email (si está configurado)
    if command -v mail >/dev/null 2>&1 && [ ! -z "$ALERT_EMAIL" ]; then
        echo "$message" | mail -s "ALERTA: Sistema de Tickets IT" $ALERT_EMAIL
    fi
    
    # Enviar por webhook (si está configurado)
    if [ ! -z "$WEBHOOK_URL" ]; then
        local emoji="⚠️"
        if [ "$severity" = "critical" ]; then
            emoji="🚨"
        fi
        
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$emoji ALERTA Sistema de Tickets IT\\n$message\"}" \
            $WEBHOOK_URL 2>/dev/null || true
    fi
}

# =====================================================
# VERIFICACIÓN DE SERVICIOS CRÍTICOS
# =====================================================

check_services() {
    info "🔍 Verificando servicios críticos..."
    
    local services=("nginx" "mysql" "pm2")
    local failed_services=()
    
    for service in "${services[@]}"; do
        if [ "$service" = "pm2" ]; then
            # Verificar PM2 de manera especial
            if ! pm2 list | grep -q "$APP_NAME.*online"; then
                failed_services+=("$service")
                send_alert "Servicio PM2 ($APP_NAME) no está ejecutándose" "critical"
            else
                log "✅ PM2 ($APP_NAME) funcionando correctamente"
            fi
        else
            if ! systemctl is-active --quiet $service; then
                failed_services+=("$service")
                send_alert "Servicio $service no está ejecutándose" "critical"
            else
                log "✅ $service funcionando correctamente"
            fi
        fi
    done
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        log "✅ Todos los servicios críticos funcionando"
    else
        error "❌ Servicios fallidos: ${failed_services[*]}"
    fi
}

# =====================================================
# VERIFICACIÓN DE RECURSOS DEL SISTEMA
# =====================================================

check_system_resources() {
    info "📊 Verificando recursos del sistema..."
    
    # CPU
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    CPU_USAGE=${CPU_USAGE%.*}  # Remover decimales
    
    if [ "$CPU_USAGE" -gt "$CPU_THRESHOLD" ]; then
        send_alert "Uso de CPU alto: ${CPU_USAGE}% (umbral: ${CPU_THRESHOLD}%)" "warning"
    else
        log "✅ CPU: ${CPU_USAGE}%"
    fi
    
    # Memoria
    MEMORY_INFO=$(free | grep Mem)
    MEMORY_TOTAL=$(echo $MEMORY_INFO | awk '{print $2}')
    MEMORY_USED=$(echo $MEMORY_INFO | awk '{print $3}')
    MEMORY_USAGE=$((MEMORY_USED * 100 / MEMORY_TOTAL))
    
    if [ "$MEMORY_USAGE" -gt "$MEMORY_THRESHOLD" ]; then
        send_alert "Uso de memoria alto: ${MEMORY_USAGE}% (umbral: ${MEMORY_THRESHOLD}%)" "warning"
    else
        log "✅ Memoria: ${MEMORY_USAGE}%"
    fi
    
    # Disco
    DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
        send_alert "Uso de disco alto: ${DISK_USAGE}% (umbral: ${DISK_THRESHOLD}%)" "warning"
    else
        log "✅ Disco: ${DISK_USAGE}%"
    fi
    
    # Carga del sistema
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    log "📈 Carga promedio: $LOAD_AVG"
}

# =====================================================
# VERIFICACIÓN DE CONECTIVIDAD WEB
# =====================================================

check_web_connectivity() {
    info "🌐 Verificando conectividad web..."
    
    # Obtener dominio del archivo .env
    local domain="http://localhost:3000"
    if [ -f "$APP_DIR/.env" ]; then
        domain=$(grep "^DOMAIN=" "$APP_DIR/.env" | cut -d'=' -f2)
    fi
    
    # Verificar respuesta HTTP
    local start_time=$(date +%s%3N)
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 $domain 2>/dev/null || echo "000")
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    if [ "$http_status" = "200" ]; then
        if [ "$response_time" -gt "$RESPONSE_TIME_THRESHOLD" ]; then
            send_alert "Tiempo de respuesta lento: ${response_time}ms (umbral: ${RESPONSE_TIME_THRESHOLD}ms)" "warning"
        else
            log "✅ Web respondiendo: ${response_time}ms"
        fi
    else
        send_alert "Sitio web no responde correctamente (HTTP $http_status)" "critical"
    fi
}

# =====================================================
# VERIFICACIÓN DE BASE DE DATOS
# =====================================================

check_database() {
    info "🗄️ Verificando base de datos..."
    
    # Verificar conexión a MySQL
    if [ -f "$APP_DIR/.env" ]; then
        local db_user=$(grep "^DB_USER=" "$APP_DIR/.env" | cut -d'=' -f2)
        local db_pass=$(grep "^DB_PASSWORD=" "$APP_DIR/.env" | cut -d'=' -f2)
        local db_name=$(grep "^DB_NAME=" "$APP_DIR/.env" | cut -d'=' -f2)
        
        if mysql -u "$db_user" -p"$db_pass" -e "USE $db_name; SELECT 1;" >/dev/null 2>&1; then
            log "✅ Base de datos accesible"
            
            # Verificar número de conexiones activas
            local connections=$(mysql -u "$db_user" -p"$db_pass" -e "SHOW STATUS LIKE 'Threads_connected';" | tail -1 | awk '{print $2}')
            log "🔗 Conexiones activas: $connections"
            
            # Verificar tamaño de la base de datos
            local db_size=$(mysql -u "$db_user" -p"$db_pass" -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'DB Size in MB' FROM information_schema.tables WHERE table_schema='$db_name';" | tail -1)
            log "💾 Tamaño BD: ${db_size}MB"
            
        else
            send_alert "No se puede conectar a la base de datos" "critical"
        fi
    else
        warning "No se puede verificar BD: archivo .env no encontrado"
    fi
}

# =====================================================
# VERIFICACIÓN DE LOGS DE ERROR
# =====================================================

check_error_logs() {
    info "📋 Verificando logs de error..."
    
    # Verificar logs de PM2
    local pm2_errors=$(pm2 logs $APP_NAME --lines 50 --nostream 2>/dev/null | grep -i "error" | wc -l)
    if [ "$pm2_errors" -gt 5 ]; then
        send_alert "Muchos errores en logs de PM2: $pm2_errors errores en últimas 50 líneas" "warning"
    else
        log "✅ Logs PM2: $pm2_errors errores recientes"
    fi
    
    # Verificar logs de Nginx
    local nginx_errors=$(tail -100 /var/log/nginx/error.log 2>/dev/null | wc -l)
    if [ "$nginx_errors" -gt 10 ]; then
        warning "Errores en Nginx: $nginx_errors líneas en log de errores"
    else
        log "✅ Logs Nginx: $nginx_errors errores recientes"
    fi
    
    # Verificar logs de MySQL
    local mysql_errors=$(tail -100 /var/log/mysql/error.log 2>/dev/null | grep -i "error" | wc -l)
    if [ "$mysql_errors" -gt 0 ]; then
        warning "Errores en MySQL: $mysql_errors errores recientes"
    else
        log "✅ Logs MySQL: sin errores recientes"
    fi
}

# =====================================================
# VERIFICACIÓN DE CERTIFICADOS SSL
# =====================================================

check_ssl_certificates() {
    info "🔒 Verificando certificados SSL..."
    
    if [ -f "$APP_DIR/.env" ]; then
        local domain=$(grep "^DOMAIN=" "$APP_DIR/.env" | cut -d'=' -f2 | sed 's|https://||' | sed 's|http://||')
        
        if [ ! -z "$domain" ] && [ "$domain" != "localhost:3000" ]; then
            # Verificar expiración del certificado
            local cert_info=$(echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
            
            if [ ! -z "$cert_info" ]; then
                local expiry_date=$(echo "$cert_info" | grep "notAfter" | cut -d'=' -f2)
                local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
                local current_timestamp=$(date +%s)
                local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
                
                if [ "$days_until_expiry" -lt 30 ]; then
                    send_alert "Certificado SSL expira pronto: $days_until_expiry días" "warning"
                else
                    log "✅ SSL válido por $days_until_expiry días"
                fi
            else
                warning "No se pudo verificar certificado SSL"
            fi
        else
            log "ℹ️ SSL no aplicable (localhost o dominio no configurado)"
        fi
    fi
}

# =====================================================
# VERIFICACIÓN DE ESPACIO EN RESPALDOS
# =====================================================

check_backup_space() {
    info "💾 Verificando espacio de respaldos..."
    
    local backup_dir="/root/backups"
    if [ -d "$backup_dir" ]; then
        local backup_size=$(du -sh $backup_dir | cut -f1)
        local backup_count=$(find $backup_dir -type f | wc -l)
        
        log "📦 Respaldos: $backup_count archivos, $backup_size"
        
        # Verificar último respaldo
        local last_backup=$(find $backup_dir -name "db_backup_*.sql.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        if [ ! -z "$last_backup" ]; then
            local backup_age=$(( ($(date +%s) - $(stat -c %Y "$last_backup")) / 3600 ))
            if [ "$backup_age" -gt 25 ]; then  # Más de 25 horas
                send_alert "Último respaldo muy antiguo: hace $backup_age horas" "warning"
            else
                log "✅ Último respaldo: hace $backup_age horas"
            fi
        else
            send_alert "No se encontraron respaldos recientes" "warning"
        fi
    else
        warning "Directorio de respaldos no existe"
    fi
}

# =====================================================
# FUNCIÓN PRINCIPAL
# =====================================================

main() {
    log "🚀 Iniciando monitoreo del sistema"
    
    # Ejecutar todas las verificaciones
    check_services
    check_system_resources
    check_web_connectivity
    check_database
    check_error_logs
    check_ssl_certificates
    check_backup_space
    
    log "✅ Monitoreo completado"
    
    # Generar resumen
    echo
    echo "=================================================="
    echo "         RESUMEN DEL MONITOREO"
    echo "=================================================="
    echo "📅 Fecha: $(date)"
    echo "🖥️ Servidor: $(hostname)"
    echo "⏱️ Uptime: $(uptime -p)"
    echo "👥 Usuarios conectados: $(who | wc -l)"
    echo "🔄 Procesos activos: $(ps aux | wc -l)"
    echo "=================================================="
}

# =====================================================
# EJECUCIÓN
# =====================================================

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    warning "Se recomienda ejecutar como root para acceso completo"
fi

# Crear directorio de logs si no existe
mkdir -p $(dirname $LOG_FILE)

# Ejecutar función principal
main

# Si se pasa parámetro --continuous, ejecutar en bucle
if [ "$1" = "--continuous" ]; then
    log "🔄 Modo continuo activado (cada 5 minutos)"
    while true; do
        sleep 300  # 5 minutos
        main
    done
fi

exit 0
