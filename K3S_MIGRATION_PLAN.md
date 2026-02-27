# Plan de Migración: Docker Compose + Nginx → K3S + Traefik

**Fecha**: 26 de Febrero 2026  
**Estado**: Planificación (sin cambios en producción)  
**Objetivo**: Zero-downtime migration a K3S con Traefik

---

## 📊 SETUP ACTUAL

### Infraestructura Actual
- **Hosting**: VM en OCI
- **Runner**: self-hosted en la VM
- **Orquestación**: docker-compose
- **Reverse Proxy**: Nginx (puerto 80)
- **App**: vocational-test-app

### Workflow Actual (`deploy.yml`)
```
Push a main (GitHub)
  ↓
checkout código (self-hosted runner en VM)
  ↓
rsync a /mnt/tesis_data/codigo/vocational_test_prd/
  ↓
docker-compose build vocational-test-app (con backup de imagen)
  ↓
docker-compose stop vocational-test-app
  ↓
docker-compose up -d vocational-test-app
  ↓
health check (30s timeout) + rollback si falla
  ↓
prune imágenes viejas
```

### Ventajas Actuales
- ✅ Rollback rápido (backup de imagen)
- ✅ Validación pre-deploy (health check)
- ✅ Mantiene Nginx corriendo (zero downtime)

### Limitaciones Actuales
- ❌ No es escalable (1 contenedor)
- ❌ Sin auto-healing si el app crashea
- ❌ Sin load balancing nativo
- ❌ Estado de infra acoplado a código

---

## 🎯 ARQUITECTURA PROPUESTA

### Estructura de Repos

#### Repo 1: `GestPro-VocationalTest` (existente)
```
.
├── backend/
├── frontend/
├── Dockerfile
├── requirements.txt
├── .github/workflows/
│   ├── deploy.yml              ← Mantener (docker-compose legacy)
│   └── build-push-image.yml    ← NUEVO: Build & Push a GHCR
├── README.md
└── K3S_MIGRATION_PLAN.md       ← Este archivo
```

#### Repo 2: `GestPro-K3S-Infrastructure` (NUEVO - PRIVADO)
```
.
├── k3s/
│   ├── deployment.yaml         ← Deployment vocational-test
│   ├── service.yaml            ← ClusterIP o LoadBalancer
│   ├── configmap.yaml          ← Vars no-secretas
│   └── hpa.yaml                ← (Opcional) Auto-scaling
│
├── traefik/
│   ├── deployment.yaml         ← Traefik with hostNetwork
│   ├── service.yaml            ← LoadBalancer :80/:443
│   └── ingressroute.yaml       ← Ruteo de tráfico
│
├── scripts/
│   └── setup-k3s.sh            ← Script de bootstrapping
│
├── .github/workflows/
│   ├── validate-yaml.yml       ← Validate YAML syntax
│   ├── deploy-k3s.yml          ← Triggered: paths: k3s/**
│   └── deploy-traefik.yml      ← Triggered: paths: traefik/**
│
└── README.md                   ← Docs de infra
```

---

## ⚙️ PLAN DE MIGRACIÓN (3 FASES)

### FASE 1: Preparación (0 downtime)
```
Semana 1-2: Setup paralelo sin afectar producción

✅ Paso 1: Instalar K3S en VM
   curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" sh -

✅ Paso 2: Extraer kubeconfig
   cat /etc/rancher/k3s/k3s.yaml > ~/k3s.yaml
   # Cambiar 127.0.0.1 por IP pública de VM
   # Guardar como secret en GitHub

✅ Paso 3: Deploy Traefik en K3S (puerto 8080 interno)
   # Traefik NO en puerto 80 aún (Nginx sigue ahí)
   # Se expone internamente para testing

✅ Paso 4: Crear namespace y secrets en K3S
   kubectl create namespace vocational-test
   kubectl create secret generic app-secrets \
     --from-literal=ORACLE_USER=$SECRET \
     -n vocational-test

✅ Paso 5: Crear ConfigMap para vars no-secretas
   kubectl apply -f k3s/configmap.yaml

✅ Paso 6: Deploy app en K3S (sin exponer aún)
   # Pod corre, pero no accesible desde afuera
   kubectl apply -f k3s/deployment.yaml -n vocational-test
```

### FASE 2: Validación (testing interno)
```
Semana 3: Validar K3S antes de cutover

✅ Paso 1: Portforward a vocational-test:8000
   kubectl port-forward -n vocational-test svc/vocational-test 8000:8000

✅ Paso 2: Verificar health endpoint
   curl http://localhost:8000/api/health

✅ Paso 3: Actualizar Nginx para consumir K3S internamente
   # Config Nginx: proxy_pass http://k3s-pod-ip:8000;
   # Si falla, sigue sirviendo contenedor docker-compose

✅ Paso 4: Load testing desde outside
   # Asegurar que funciona igual que con docker-compose

✅ Paso 5: Monitorear logs en K3S
   kubectl logs -f deployment/vocational-test -n vocational-test
```

### FASE 3: Cutover (downtime mínimo ~30s)
```
Semana 4: Switch final

✅ Paso 1: Traefik: cambiar entrypoint de 8080 → 80
   # O cambiar iptables para redirigir

✅ Paso 2: DNS/Firewall apunta directo a Traefik:80
   # 1-2 minutos de latencia en propagación

✅ Paso 3: Validar tráfico en Traefik
   kubectl logs -f deployment/traefik -n traefik

✅ Paso 4: Mantener docker-compose/Nginx corriendo 24h más
   # Para rollback rápido si algo falla

✅ Paso 5: Si estable → apagar docker-compose
   docker-compose down
```

---

## 🔌 PUERTO Y TRAEFIK: DECISIÓN FINAL

### Estrategia Elegida: Traefik como LoadBalancer en Puerto 80

```
Razón: 
- K3S es nativo de Kubernetes
- Traefik como LoadBalancer es lo correcto en K8s
- Separación clara: Nginx (legacy) vs Traefik (nuevo)

Timeline:
├─ Semana 1-3: Traefik en 8080, Nginx al 80 (ambos corriendo)
├─ Semana 4: Cambio DNS → Traefik en 80
└─ Semana 4+: Nginx OFF

YAML Traefik Service:
---
apiVersion: v1
kind: Service
metadata:
  name: traefik
  namespace: traefik
spec:
  type: LoadBalancer  # ← Expone puertos 80/443 del host
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  - port: 443
    targetPort: 8443
    protocol: TCP
  selector:
    app: traefik
```

---

## 🐳 IMAGEN DOCKER: GITHUB CONTAINER REGISTRY (GHCR)

### Opción Elegida: GHCR (100% gratis para público)

```
Ventajas:
✅ 100% gratis para repos públicos
✅ Token de GitHub automático
✅ Integración nativa con Actions
✅ URL: ghcr.io/tu-usuario/GestPro-VocationalTest:latest
✅ Sin configuración de credenciales extra
✓ Rate limits mucho más altos que Docker Hub

Alternativas descartadas:
❌ OCI Registry: Gratis pero requiere credenciales extra
❌ Docker Hub: 1 repo privado, rate limits en publicos
❌ Registry interno en K3S: Punto único de fallo
```

### Workflow: `build-push-image.yml` (GestPro-VocationalTest)

```yaml
name: Build & Push Imagen a GHCR

on:
  push:
    branches: [main]
    paths:
      - 'backend/**'
      - 'frontend/**'
      - 'Dockerfile'

jobs:
  build-push:
    runs-on: self-hosted
    permissions:
      contents: read
      packages: write
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Login to GHCR
        run: |
          echo ${{ secrets.GITHUB_TOKEN }} | \
            docker login ghcr.io -u ${{ github.actor }} --password-stdin
      
      - name: Build & Push (latest + SHA)
        run: |
          docker build -t ghcr.io/${{ github.repository }}:latest \
                       -t ghcr.io/${{ github.repository }}:${{ github.sha }} .
          docker push ghcr.io/${{ github.repository }}:latest
          docker push ghcr.io/${{ github.repository }}:${{ github.sha }}
          
      - name: Trigger Infrastructure Deployment
        run: |
          curl -X POST \
            -H "Authorization: token ${{ secrets.GITHUB_TOKEN }}" \
            https://api.github.com/repos/tu-usuario/GestPro-K3S-Infrastructure/dispatches \
            -d '{"event_type":"image-updated","client_payload":{"image":"ghcr.io/${{ github.repository }}:${{ github.sha }}"}}' 
```

K3S Deployment referencia:
```yaml
spec:
  containers:
  - name: vocational-test-app
    image: ghcr.io/tu-usuario/GestPro-VocationalTest:latest
    imagePullPolicy: Always
```

---

## 🔐 GITHUB SECRETS NECESARIOS

### En `GestPro-VocationalTest` (existente principal)
```
ORACLE_USER                    ✓ (ya existe)
ORACLE_PASSWORD                ✓ (ya existe)
ORACLE_CONNECTION_STRING       ✓ (ya existe)
GROQ_API_KEY                   ✓ (ya existe)
CHAT_TEMPERATURE               ✓ (ya existe)
CHAT_SESSION_TIMEOUT           ✓ (ya existe)
CHAT_RATE_LIMIT                ✓ (ya existe)
CHAT_MAX_RESPONSE_TOKENS       ✓ (ya existe)
CHAT_MAX_MESSAGE_LENGTH        ✓ (ya existe)
OCI_PREAUTH_URL_READ           ✓ (ya existe)

GITHUB_TOKEN                   ✓ (automático)
```

### En `GestPro-K3S-Infrastructure` (NUEVO repo)
```
KUBECONFIG_B64                 ← NEW: Contenido de k3s.yaml en base64
K3S_API_SERVER                 ← NEW: https://IP-PUBLICA-VM:6443
K3S_CONTEXT                    ← NEW: "default" (o tu contexto)

# Heredar del workflow anterior:
ORACLE_USER                    ← De GestPro-VocationalTest
ORACLE_PASSWORD                ← De GestPro-VocationalTest
... (resto de secrets de app si K3S los necesita)
```

---

## 🔄 WORKFLOWS NECESARIOS

### Workflow 1: `build-push-image.yml` (GestPro-VocationalTest)
**Triggers**: Push a main con cambios en backend/, frontend/, Dockerfile

**Acciones**:
1. Build imagen desde Dockerfile
2. Push tag `latest` a GHCR
3. Push tag `git-sha` a GHCR para trazabilidad
4. Dispara webhook a GestPro-K3S-Infrastructure

---

### Workflow 2: `deploy-k3s.yml` (GestPro-K3S-Infrastructure)
**Triggers**: 
- Cambios en `k3s/` 
- O webhook desde GestPro-VocationalTest

**Acciones**:
```bash
# Setup kubeconfig
echo "$KUBECONFIG_B64" | base64 -d > /tmp/kubeconfig
export KUBECONFIG=/tmp/kubeconfig

# Deploy a K3S
kubectl apply -f k3s/ -n vocational-test

# Wait for rollout
kubectl rollout status deployment/vocational-test -n vocational-test --timeout=5m

# Health check
HEALTH=$(curl -s http://vocational-test-service:8000/api/health | jq .status)
if [ "$HEALTH" != "ok" ]; then
  echo "Health check failed"
  kubectl rollout undo deployment/vocational-test -n vocational-test
  exit 1
fi
```

**Rollback automático** si falla:
```bash
kubectl rollout undo deployment/vocational-test -n vocational-test
```

---

### Workflow 3: `deploy-traefik.yml` (GestPro-K3S-Infrastructure)
**Triggers**: Cambios en `traefik/`

**Acciones**:
```bash
kubectl apply -f traefik/ -n traefik
kubectl rollout status deployment/traefik -n traefik --timeout=5m
```

---

### Workflow 4: `validate-yaml.yml` (GestPro-K3S-Infrastructure)
**Triggers**: Cualquier push a main

**Acciones**:
```bash
# Validar sintaxis YAML
yamllint k3s/ traefik/

# Validar contra esquema K8s
kubeval k3s/*.yaml traefik/*.yaml

# Dry-run contra K3S
kubectl apply -f k3s/ -n vocational-test --dry-run=server
kubectl apply -f traefik/ -n traefik --dry-run=server
```

---

## 🛠️ KUBERNETES: GESTIÓN REMOTA CON KUBECONFIG

### SÍ, 100% posible gestionar K3S desde afuera

#### Desde tu máquina local:
```bash
# 1. Obtener kubeconfig desde VM (vía SSH)
scp usuario@vm-ip:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-config

# 2. Editar para acceso remoto (IMPORTANTE)
# Original:
#   server: https://127.0.0.1:6443
# Cambiar por:
#   server: https://IP-PUBLICA-VM:6443

sed -i 's/127.0.0.1/IP-PUBLICA-VM/g' ~/.kube/k3s-config

# 3. Probar conexión
kubectl --kubeconfig ~/.kube/k3s-config get nodes
kubectl --kubeconfig ~/.kube/k3s-config get pods -A

# 4. Usar por defecto (opcional)
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes
```

#### Desde GitHub Actions:
```yaml
- name: Setup kubeconfig
  env:
    KUBECONFIG_B64: ${{ secrets.KUBECONFIG_B64 }}
  run: |
    echo "$KUBECONFIG_B64" | base64 -d > /tmp/kubeconfig
    chmod 600 /tmp/kubeconfig
    export KUBECONFIG=/tmp/kubeconfig
    kubectl get nodes  # Validar conexión

- name: Deploy
  run: |
    export KUBECONFIG=/tmp/kubeconfig
    kubectl apply -f k3s/ -n vocational-test
```

#### Guardar kubeconfig en GitHub Secrets:
```bash
# En local:
cat ~/.kube/k3s-config | base64 -w 0 > /tmp/kubeconfig.b64
echo "Copia esto en GitHub Secrets como KUBECONFIG_B64:"
cat /tmp/kubeconfig.b64
```

---

## 📈 CONFIGURACIÓN TÉCNICA

### Health Check Endpoint
Necesitas un endpoint en tu app (ej: `/api/health`):

```python
# backend/routes/health_routes.py
@app.route('/api/health')
def health():
    try:
        # Verificar conexión DB
        check_db_connection()
        
        return {
            'status': 'ok',
            'timestamp': datetime.now().isoformat(),
            'version': '1.0.0'
        }, 200
    except Exception as e:
        return {
            'status': 'error',
            'error': str(e)
        }, 500
```

K3S Readiness Probe:
```yaml
readinessProbe:
  httpGet:
    path: /api/health
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 3
```

K3S Liveness Probe:
```yaml
livenessProbe:
  httpGet:
    path: /api/health
    port: 8000
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 2
  failureThreshold: 3
```

### Recursos (CPU/Memory)
Recomendado para vocational-test:
```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 1Gi
```

### Réplicas y Rolling Update
Configuración para zero downtime:
```yaml
replicas: 2
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # 1 pod nuevo mientras se termina el viejo
    maxUnavailable: 0  # CERO indisponibles = zero downtime
```

### Logs y Debugging
```bash
# Ver logs en tiempo real
kubectl logs -f deployment/vocacional-test -n vocational-test

# Ver logs de un pod específico
kubectl logs POD_NAME -n vocational-test

# Últimas 100 líneas
kubectl logs --tail=100 -n vocational-test deployment/vocational-test

# Ver logs de contenedor anterior (si crashea)
kubectl logs -p POD_NAME -n vocational-test
```

---

## 🎯 CHECKPOINTS DE VALIDACIÓN

### Antes de Fase 2: K3S + Traefik instalados
```
[ ] K3S instalado: kubectl get nodes
[ ] Traefik corriendo: kubectl get pods -n traefik
[ ] Secrets creados: kubectl get secrets -n vocational-test
[ ] ConfigMap creado: kubectl get cm -n vocational-test
[ ] Kubeconfig funciona desde afuera
```

### Después de deploy inicial:
```
[ ] Pod en running: kubectl get pods -n vocational-test
[ ] Logs limpios: kubectl logs -f deploy/vocational-test -n vocational-test
[ ] Health check OK: curl http://pod-ip:8000/api/health
[ ] Nginx → K3S proxy funciona
```

### Antes de cutover:
```
[ ] Tráfico por Nginx → K3S OK (1-2 días)
[ ] Load test sin errores
[ ] Rollback manual probado: kubectl rollout undo ...
[ ] DNS listo para cambiar
```

### Después de cutover:
```
[ ] DNS apunta a Traefik
[ ] Tráfico por Traefik:80 sin errores
[ ] Nginx aún corriendo (fallback 24h)
[ ] Monitoreo activo logs de Traefik
[ ] Sin incidents reportados
```

### Semana después de cutover:
```
[ ] Sin errores en logs en 7 días
[ ] Shutdown docker-compose seguro
[ ] Cleanup de VMs/espacios antiguos
```

---

## 📞 COMANDOS ÚTILES K3S

### Información General
```bash
# Ver configuración actual
kubectl config view

# Listar todos los nodos
kubectl get nodes

# Listar todos los namespaces
kubectl get ns

# Info del cluster
kubectl cluster-info
```

### Namespace: vocational-test
```bash
# Listar pods
kubectl get pods -n vocational-test

# Describir un pod (detalles)
kubectl describe pod POD_NAME -n vocational-test

# Ver logs en tiempo real
kubectl logs -f deployment/vocational-test -n vocational-test

# Ver últimas 100 líneas
kubectl logs -f deployment/vocational-test -n vocational-test --tail=100

# Ejecutar comando dentro del pod
kubectl exec -it POD_NAME -n vocational-test -- sh

# Portforward local a servicio
kubectl port-forward -n vocational-test svc/vocational-test 8000:8000
```

### Updates y Rollback
```bash
# Actualizar imagen
kubectl set image deployment/vocational-test \
  app=ghcr.io/usuario/repo:nuevo-tag \
  -n vocational-test

# Ver estado del rollout
kubectl rollout status deployment/vocational-test -n vocational-test

# Ver historial de rollouts
kubectl rollout history deployment/vocational-test -n vocational-test

# Rollback a versión anterior
kubectl rollout undo deployment/vocational-test -n vocational-test

# Rollback a revisión específica
kubectl rollout undo deployment/vocational-test --to-revision=2 -n vocational-test
```

### Traefik Monitoring
```bash
# Ver logs de Traefik
kubectl logs -f deployment/traefik -n traefik

# Listar IngressRoutes
kubectl get ingressroute -n vocational-test

# Ver detalles de un IngressRoute
kubectl describe ingressroute vocational-test -n vocational-test

# Validar Traefik está escuchando puertos
kubectl get svc traefik -n traefik
```

### Debugging Avanzado
```bash
# Ver eventos del cluster
kubectl get events -n vocational-test

# Ver información de recursos usados
kubectl top nodes
kubectl top pod -n vocational-test

# Ver definición completa de un recurso
kubectl get deployment vocational-test -n vocational-test -o yaml

# Aplicar cambios desde YAML local
kubectl apply -f k3s/deployment.yaml -n vocational-test

# Dry-run para ver qué haría
kubectl apply -f k3s/deployment.yaml -n vocational-test --dry-run=server

# Delete un recurso
kubectl delete deployment vocational-test -n vocational-test
```

---

## 📝 TIMELINE ESTIMADO

```
Semana 1-2: FASE 1 - Preparación
  Día 1-2: Instalar K3S en VM
  Día 3-4: Deploy Traefik (puerto 8080)
  Día 5-6: ConfigMap + Secrets K3S
  Día 7-8: Workflow setup en GitHub
  Día 9-10: Deploy vocational-test en K3S
  Día 11-14: Testing interno, healthchecks

Semana 3: FASE 2 - Validación
  Día 15-16: Portforward + curl tests
  Día 17-18: Nginx proxy a K3S
  Día 19-21: Load testing (48h sostenido)

Semana 4: FASE 3 - Cutover
  Día 22: Traefik en puerto 80
  Día 23: DNS switch (o HTTP redirect)
  Día 24-27: Monitoreo 24/7
  Día 28: Shutdown docker-compose

Post-Cutover (Semana 5+):
  - Optimization (HPA, resources)
  - Cleanup (remove nginx config)
  - Documentation update
  - Team training on kubectl
```

---

## ✅ PRÓXIMOS PASOS INMEDIATOS

1. **Crear repo `GestPro-K3S-Infrastructure`** (privado en GitHub)
2. **Instalar K3S en VM** (puede ser en paralelo)
3. **Generar kubeconfig y agregarlo como secret**
4. **Crear YAML templates**:
   - `k3s/deployment.yaml` (vocational-test)
   - `k3s/service.yaml` (ClusterIP)
   - `k3s/configmap.yaml` (variables)
   - `traefik/deployment.yaml` (Traefik)
   - `traefik/ingressroute.yaml` (ruteo)
5. **Crear workflows GitHub Actions** (validate, deploy-k3s, deploy-traefik)
6. **Agregar `build-push-image.yml`** a GestPro-VocationalTest
7. **Prueba de concepto** en dev antes de producción

---

## 📚 REFERENCIAS ÚTILES

- **K3S Docs**: https://docs.k3s.io
- **K3S con Traefik**: https://docs.k3s.io/networking/traefik
- **kubectl Cheatsheet**: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
- **GitHub Container Registry**: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- **Traefik IngressRoute**: https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/
- **Kubernetes Best Practices**: https://kubernetes.io/docs/concepts/configuration/overview/

---

**Documento actualizado**: 26 Febrero 2026  
**Status**: ✅ Plan completo - Listo para iniciar Fase 1  
**Responsable**: Tu nombre  
**Próxima revisión**: Después de instalar K3S en VM
