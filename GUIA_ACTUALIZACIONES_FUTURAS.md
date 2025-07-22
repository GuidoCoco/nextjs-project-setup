# 🔄 GUÍA DE ACTUALIZACIONES Y MANTENIMIENTO
## Sistema de Tickets IT - VENTURINO

### 📋 RESUMEN
Esta guía te explica cómo manejar actualizaciones futuras del sistema cuando necesites agregar nuevas funciones o hacer cambios.

---

## 🎯 ESCENARIOS DE ACTUALIZACIÓN

### **Escenario 1: Agregar nuevas funciones (Recomendado)**
Cuando me pidas agregar funciones, seguiremos este proceso:

#### **Paso 1: Preparación**
```bash
# En tu servidor de producción
cd /var/www/it-ticket-system
./scripts/backup.sh  # Crear respaldo completo
```

#### **Paso 2: Desarrollo**
- Me envías la solicitud de nueva función
- Yo modifico/creo los archivos necesarios
- Te proporciono los archivos actualizados
- Te doy instrucciones específicas de qué cambió

#### **Paso 3: Aplicar cambios**
```bash
# Descargar archivos actualizados (ejemplo)
wget https://enlace-a-archivo-actualizado.js -O server/routes/nueva-ruta.js

# O si usas Git (recomendado)
git pull origin main
```

#### **Paso 4: Actualizar dependencias (si es necesario)**
```bash
npm install  # Solo si agregué nuevas dependencias
```

#### **Paso 5: Actualizar base de datos (si es necesario)**
```bash
# Si hay cambios en BD, te proporcionaré un script como:
mysql -u tickets_user -p venturino_tickets_db < actualizacion_v2.sql
```

#### **Paso 6: Desplegar cambios**
```bash
./scripts/deploy.sh  # Usa el script automático
```

---

## 🔧 CONFIGURACIÓN RECOMENDADA: GIT

### **Opción A: Usar Git (MUY RECOMENDADO)**

#### **Configuración inicial:**
```bash
# En tu servidor
cd /var/www/it-ticket-system
git init
git remote add origin https://github.com/tu-usuario/venturino-tickets.git
git add .
git commit -m "Versión inicial en producción"
git push -u origin main
```

#### **Para futuras actualizaciones:**
1. Yo hago los cambios en el repositorio
2. Tú ejecutas en el servidor:
```bash
cd /var/www/it-ticket-system
git pull origin main
./scripts/deploy.sh
```

### **Ventajas del Git:**
✅ Control de versiones  
✅ Fácil rollback si algo falla  
✅ Historial de cambios  
✅ Actualizaciones automáticas  

---

## 📁 ESTRUCTURA DE ACTUALIZACIONES

### **Tipos de cambios que puedo hacer:**

#### **1. Cambios de Frontend (HTML/CSS/JS)**
- **Archivos afectados:** `/public/`
- **Requiere reinicio:** ❌ No
- **Comando:** Solo recargar navegador

#### **2. Cambios de Backend (Node.js)**
- **Archivos afectados:** `/server/`
- **Requiere reinicio:** ✅ Sí
- **Comando:** `pm2 restart tickets-system`

#### **3. Cambios de Base de Datos**
- **Archivos afectados:** `/database/`
- **Requiere script:** ✅ Sí
- **Comando:** `mysql -u user -p db < script.sql`

#### **4. Nuevas dependencias**
- **Archivos afectados:** `package.json`
- **Requiere instalación:** ✅ Sí
- **Comando:** `npm install`

---

## 🚀 PROCESO PASO A PASO PARA ACTUALIZACIONES

### **Cuando me pidas una nueva función:**

#### **1. Tu solicitud debe incluir:**
- Descripción detallada de la función
- Cómo debe funcionar
- Qué usuarios pueden usarla
- Capturas de pantalla si es visual

#### **2. Yo te entregaré:**
- Archivos modificados/nuevos
- Script SQL (si hay cambios en BD)
- Instrucciones específicas
- Lista de verificación

#### **3. Tú ejecutarás:**
```bash
# Paso 1: Respaldo
./scripts/backup.sh

# Paso 2: Descargar cambios
git pull origin main
# O descargar archivos manualmente

# Paso 3: Instalar dependencias (si es necesario)
npm install

# Paso 4: Actualizar BD (si es necesario)
mysql -u tickets_user -p venturino_tickets_db < actualizacion.sql

# Paso 5: Desplegar
./scripts/deploy.sh

# Paso 6: Verificar
curl https://tudominio.com/health
```

---

## 📋 EJEMPLOS DE ACTUALIZACIONES COMUNES

### **Ejemplo 1: Agregar nueva página**
**Archivos que cambiarían:**
- `public/nueva-pagina.html` (nuevo)
- `public/js/nueva-funcionalidad.js` (nuevo)
- `server/routes/nueva-ruta.js` (nuevo)
- `public/dashboard.html` (modificado - agregar enlace)

**Pasos:**
1. Respaldo
2. Subir archivos nuevos
3. `pm2 restart tickets-system`
4. Verificar funcionamiento

### **Ejemplo 2: Agregar campo a tickets**
**Archivos que cambiarían:**
- `database/actualizacion_v2.sql` (nuevo)
- `server/routes/tickets.js` (modificado)
- `public/js/tickets.js` (modificado)
- `public/dashboard.html` (modificado)

**Pasos:**
1. Respaldo
2. Ejecutar script SQL
3. Subir archivos modificados
4. `pm2 restart tickets-system`
5. Verificar funcionamiento

### **Ejemplo 3: Integrar con API externa**
**Archivos que cambiarían:**
- `package.json` (nueva dependencia)
- `server/utils/api-externa.js` (nuevo)
- `.env` (nuevas variables)
- `server/routes/integracion.js` (nuevo)

**Pasos:**
1. Respaldo
2. `npm install`
3. Actualizar `.env`
4. Subir archivos nuevos
5. `pm2 restart tickets-system`
6. Verificar funcionamiento

---

## 🔒 SEGURIDAD EN ACTUALIZACIONES

### **Antes de cada actualización:**
```bash
# 1. Respaldo completo
./scripts/backup.sh

# 2. Verificar estado actual
./scripts/monitor.sh

# 3. Anotar versión actual
git log --oneline -1  # Si usas Git
```

### **Después de cada actualización:**
```bash
# 1. Verificar servicios
systemctl status nginx mysql
pm2 status

# 2. Probar funcionalidad básica
curl https://tudominio.com
curl https://tudominio.com/api/health

# 3. Revisar logs
pm2 logs tickets-system --lines 20
tail -f /var/log/nginx/error.log
```

### **Si algo falla (Rollback):**
```bash
# Opción 1: Rollback con Git
git reset --hard HEAD~1
pm2 restart tickets-system

# Opción 2: Restaurar desde respaldo
# (Instrucciones en GUIA_IMPLEMENTACION_PRODUCCION.md)
```

---

## 📞 COMUNICACIÓN PARA ACTUALIZACIONES

### **Formato de solicitud recomendado:**
```
SOLICITUD DE ACTUALIZACIÓN

Función solicitada: [Descripción breve]

Detalles:
- ¿Qué debe hacer?
- ¿Quién puede usarla?
- ¿Cómo debe verse?

Prioridad: Alta/Media/Baja

Fecha límite: [Si aplica]

Información adicional:
- Capturas de pantalla
- Ejemplos de otros sistemas
- Requisitos específicos
```

### **Lo que yo te entregaré:**
```
ACTUALIZACIÓN LISTA

Archivos modificados:
- server/routes/nueva-funcion.js (nuevo)
- public/js/dashboard.js (modificado líneas 45-67)
- database/actualizacion_v2.sql (nuevo)

Dependencias nuevas:
- axios (para API externa)

Variables de entorno nuevas:
- API_KEY_EXTERNA=tu_clave_aqui

Instrucciones:
1. [Paso específico 1]
2. [Paso específico 2]
3. [Paso específico 3]

Verificación:
- Probar función X en página Y
- Verificar que usuarios Z pueden acceder

Rollback (si falla):
- git reset --hard abc123
```

---

## 🎯 MEJORES PRÁCTICAS

### **Para ti:**
✅ Siempre hacer respaldo antes de actualizar  
✅ Probar en horario de menor uso  
✅ Tener plan de rollback listo  
✅ Comunicar mantenimiento a usuarios  
✅ Verificar funcionamiento después  

### **Para mí:**
✅ Documentar todos los cambios  
✅ Proporcionar instrucciones claras  
✅ Incluir scripts de verificación  
✅ Considerar compatibilidad hacia atrás  
✅ Probar antes de entregar  

---

## 📊 CRONOGRAMA TÍPICO DE ACTUALIZACIÓN

| Tiempo | Actividad |
|--------|-----------|
| T-24h | Solicitud de actualización |
| T-12h | Desarrollo y testing |
| T-2h | Entrega de archivos |
| T-1h | Respaldo del sistema |
| T | Aplicar actualización |
| T+15min | Verificación básica |
| T+1h | Monitoreo completo |
| T+24h | Verificación estabilidad |

---

## 🚨 CONTACTO DE EMERGENCIA

### **Si algo falla después de una actualización:**

1. **Rollback inmediato:**
```bash
git reset --hard HEAD~1  # Si usas Git
pm2 restart tickets-system
```

2. **Restaurar desde respaldo:**
```bash
# Seguir instrucciones en GUIA_IMPLEMENTACION_PRODUCCION.md
# Sección "Restauración de emergencia"
```

3. **Contactarme con:**
- Descripción del problema
- Logs de error
- Pasos que seguiste
- Estado actual del sistema

---

## 🎉 RESUMEN

**Para futuras actualizaciones:**

1. **Configura Git** (muy recomendado)
2. **Solicita cambios** con detalles claros
3. **Haz respaldo** antes de aplicar
4. **Sigue mis instrucciones** paso a paso
5. **Verifica funcionamiento** después
6. **Ten plan de rollback** listo

**¡El sistema está diseñado para crecer contigo!** 🚀

---

*Última actualización: Diciembre 2024*  
*Tiempo típico de actualización: 30-60 minutos*  
*Disponibilidad durante actualización: 99.5%*
