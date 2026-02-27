# K3S Infrastructure - Vocational Test

Infraestructura como código (IaC) para desplegar **Vocational Test App** en K3S con Traefik.

---

## 📁 Estructura del Repositorio

```
.
├── Vocational_Test/                    # Manifests de la aplicación
│   ├── deployment.yaml                 # Deployment (1 replica)
│   ├── service.yaml                    # ClusterIP Service
│   ├── configmap.yaml                  # Variables de entorno no-secretas
│   └── secretsTemplate.yaml            # Template de secretos (NO COMITEAR)
│
├── traefik/                            # Manifests de Traefik (reverse proxy)
│   ├── deployment.yaml                 # Traefik deployment (hostNetwork:true)
│   ├── service.yaml                    # Service + RBAC para Traefik
│   └── ingressroute.yaml               # Rutas HTTP (vocational-test.ikigais.app)
│
├── .github/workflows/                  # GitHub Actions
│   ├── validate-yaml.yml               # Valida sintaxis YAML
│   ├── deploy-k3s.yml                  # Deploy Vocational_Test + crea Secrets
│   └── deploy-traefik.yml              # Deploy/update Traefik
│
└── README.md                           # Este archivo
```

---

## 🔧 Setup Inicial

### 1. **Preparar K3S en la VM**

```bash
# Instalar K3S
curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" sh -

# Extraer kubeconfig
cat /etc/rancher/k3s/k3s.yaml > ~/k3s.yaml

# Editar: Cambiar 127.0.0.1 por IP pública de la VM
sed -i 's/127.0.0.1/YOUR_VM_PUBLIC_IP/g' ~/k3s.yaml

# Codificar en base64 (para GitHub Secrets)
cat ~/k3s.yaml | base64 -w 0 > /tmp/kubeconfig.b64
echo "Copia todo el contenido de /tmp/kubeconfig.b64 a GitHub Secrets como KUBECONFIG_B64"
```

### 2. **Agregar GitHub Secrets**

En el repositorio, ir a **Settings → Secrets and variables → Actions**

Agregar los siguientes secrets:

```
KUBECONFIG_B64              # ← De paso 1 (base64 del k3s.yaml)
ORACLE_USER                 # ← De GestPro-VocationalTest
ORACLE_PASSWORD             # ← De GestPro-VocationalTest
ORACLE_CONNECTION_STRING    # ← De GestPro-VocationalTest
GROQ_API_KEY                # ← De GestPro-VocationalTest
OCI_PREAUTH_URL_READ        # ← De GestPro-VocationalTest
OCI_PREAUTH_URL_WRITE       # ← De GestPro-VocationalTest
SECRET_KEY                  # ← De GestPro-VocationalTest
```

### 3. **Deploy inicial**

```bash
# Opción A: Via GitHub Actions (recomendado)
# Push a main → Trigger automático de deploy-k3s.yml

# Opción B: Manual (local)
export KUBECONFIG=~/k3s.yaml

# Deploy Traefik
kubectl apply -f traefik/ -n traefik --create-namespace

# Crear secrets
kubectl create secret generic vocational-test-secrets \
  --from-literal=ORACLE_USER="$ORACLE_USER" \
  --from-literal=ORACLE_PASSWORD="$ORACLE_PASSWORD" \
  --from-literal=ORACLE_CONNECTION_STRING="$ORACLE_CONNECTION_STRING" \
  --from-literal=GROQ_API_KEY="$GROQ_API_KEY" \
  --from-literal=OCI_PREAUTH_URL_READ="$OCI_PREAUTH_URL_READ" \
  --from-literal=OCI_PREAUTH_URL_WRITE="$OCI_PREAUTH_URL_WRITE" \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  -n vocational-test --create-namespace

# Deploy Vocational Test
kubectl apply -f Vocational_Test/ -n vocational-test
```

---

## 🌐 Arquitectura de Red

```
┌─────────────────────────────────────────────────────────────────┐
│ Internet                                                         │
│ ikigais.app (HTTPS:443) ← LB Externo OCI                        │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Redirige HTTP
                               ▼
            ┌──────────────────────────────────────┐
            │ VM (OCI) - Puerto 80 HTTP            │
            │ 192.168.x.x:80                       │
            └─────────────────┬────────────────────┘
                              │
            ┌─────────────────▼────────────────────┐
            │ K3S Cluster                          │
            │ ┌──────────────────────────────────┐ │
            │ │ Traefik (hostNetwork:true)       │ │
            │ │ - Escucha puerto 80 del host    │ │
            │ │ - Router interno de tráfico      │ │
            │ └──────────────────┬───────────────┘ │
            │                    │                  │
            │    ┌───────────────┼───────────────┐ │
            │    │               │               │ │
            │    ▼               ▼               ▼ │
            │ ┌─────────┐    ┌─────────┐    ┌─────────┐
            │ │Vocational   │ Proyecto │    │ Proyecto │
            │ │Test (8000)  │2 (xxxx)  │    │3 (xxxx)  │
            │ └─────────┘    └─────────┘    └─────────┘
            │
            │ Hostname Routing:
            │ vocational-test.ikigais.app  → Vocational Test
            │ proyecto2.ikigais.app        → Proyecto 2 (futuro)
            │ proyecto3.ikigais.app        → Proyecto 3 (futuro)
            └──────────────────────────────────────┘
```

---

## 📋 Configuración de Vocational Test

### **Deployment**
- **Replicas**: 1 (estable)
- **Image**: `ghcr.io/gabrielwyp/gestpro-vocationaltest:main-0f2f063`
- **Puerto**: 8000 (interno)
- **Health check**: `/health` (HTTP GET)

### **Recursos**
- **Requests**: 250m CPU, 512Mi RAM
- **Limits**: 500m CPU, 1Gi RAM

### **Probes**
- **Readiness**: Cada 10s, timeout 5s, falla después de 3 intentos
- **Liveness**: Cada 30s, timeout 5s, falla después de 3 intentos
- **Startup**: Cada 5s, timeout 3s, máximo 150s para startup

### **Upgrade Strategy**
- **RollingUpdate**: maxSurge=1, maxUnavailable=0 (zero downtime)

---

## 🚀 Workflows de CI/CD

### **1. validate-yaml.yml**
Valida sintaxis YAML en cada push a main.

```bash
# Triggers
- Push a main (cualquier cambio)
- Pull requests a main

# Checks
- kubeval: Valida contra schema K8s
- yamllint: Lint YAML
- Estructura de requiredFields (apiVersion, kind)
```

### **2. deploy-k3s.yml**
Deploy de Vocational Test en K3S.

```bash
# Triggers
- Manualmente (workflow_dispatch)
- Input: image-tag (e.g., git SHA)

# Pasos
1. Valida YAML (via validate job)
2. Setup kubeconfig desde KUBECONFIG_B64
3. Crea namespaces (traefik, vocational-test)
4. Crea Secret desde GitHub Secrets
5. Aplica manifests de Traefik
6. Aplica manifests de Vocational_Test
7. Espera rollout (5m timeout)
8. Prueba health check (/health)
9. Rollback si falla
```

### **3. deploy-traefik.yml**
Deploy de Traefik (se dispara al cambiar traefik/*).

```bash
# Triggers
- Push a main con cambios en traefik/
- Manualmente (workflow_dispatch)

# Pasos
1. Valida YAML de Traefik
2. Setup kubeconfig
3. Crea namespace traefik
4. Aplica manifests
5. Espera rollout (5m)
6. Verifica /ping endpoint
7. Rollback si falla
```

---

## 📊 Comandos Útiles

### **Ver estado de namespaces**
```bash
export KUBECONFIG=~/k3s.yaml

# Namespaces
kubectl get ns

# Pods en vocational-test
kubectl get pods -n vocational-test
kubectl describe pod <POD_NAME> -n vocational-test
kubectl logs -f deployment/vocational-test -n vocational-test

# Pods en traefik
kubectl get pods -n traefik
kubectl logs -f deployment/traefik -n traefik

# Services
kubectl get svc -n vocational-test
kubectl get svc -n traefik

# IngressRoutes
kubectl get ingressroute -n vocational-test
kubectl describe ingressroute vocational-test -n vocational-test
```

### **Actualizar imagen**
```bash
# Manualmente
kubectl set image deployment/vocational-test \
  vocational-test-app=ghcr.io/gabrielwyp/gestpro-vocationaltest:new-tag \
  -n vocational-test

# Ver rollout
kubectl rollout status deployment/vocational-test -n vocational-test

# Rollback
kubectl rollout undo deployment/vocational-test -n vocational-test
```

### **Health checks**
```bash
# Port-forward
kubectl port-forward -n vocational-test svc/vocational-test 8000:8000

# Test health endpoint
curl http://localhost:8000/health

# Ver eventos
kubectl get events -n vocational-test --sort-by='.lastTimestamp'
```

### **Logs en tiempo real**
```bash
# Traefik
kubectl logs -f deployment/traefik -n traefik

# Vocational Test
kubectl logs -f deployment/vocational-test -n vocational-test

# Pod específico
kubectl logs -f <POD_NAME> -n vocational-test
```

---

## 🔐 Gestión de Secrets

### **Crear/Actualizar secrets**

**Vía GitHub Actions** (automático en deploy-k3s.yml):
```bash
# El workflow inyecta desde GitHub Secrets automaticamente
# No necesitas hacer nada manual
```

**Vía kubectl** (manual local):
```bash
export KUBECONFIG=~/k3s.yaml

kubectl create secret generic vocational-test-secrets \
  --from-literal=ORACLE_USER="user" \
  --from-literal=ORACLE_PASSWORD="pass" \
  ... \
  -n vocational-test \
  --dry-run=client -o yaml | kubectl apply -f -
```

### **Ver secrets (nombres, no valores)**
```bash
kubectl get secrets -n vocational-test
kubectl describe secret vocational-test-secrets -n vocational-test
```

### **Rotar secrets**
```bash
# Actualizar valor en GitHub Secrets (Settings → Secrets)
# Luego trigger deploy-k3s.yml manualmente

# O manual:
kubectl delete secret vocational-test-secrets -n vocational-test
kubectl create secret generic vocational-test-secrets \
  --from-literal=ORACLE_USER="new_value" \
  ... \
  -n vocational-test

# Forzar rollout para que use nuevo secret
kubectl rollout restart deployment/vocational-test -n vocational-test
```

---

## 🔍 Troubleshooting

### **Pod no inicia**
```bash
# Ver descripción
kubectl describe pod <POD_NAME> -n vocational-test

# Ver logs
kubectl logs <POD_NAME> -n vocational-test
kubectl logs --previous <POD_NAME> -n vocational-test  # Si crasheó

# Ver eventos
kubectl get events -n vocational-test
```

### **Health check falla**
```bash
# Conectar al pod
kubectl exec -it <POD_NAME> -n vocational-test -- /bin/bash

# Desde dentro del pod:
curl http://localhost:8000/health
ps aux  # Ver procesos
```

### **Traefik no rutea tráfico**
```bash
# Ver logs de Traefik
kubectl logs -f deployment/traefik -n traefik

# Ver IngressRoute
kubectl describe ingressroute vocational-test -n vocational-test

# Verificar service existe
kubectl get svc vocational-test -n vocational-test

# Test conectividad desde Traefik pod
kubectl exec -it <TRAEFIK_POD> -n traefik -- \
  curl http://vocational-test.vocational-test.svc.cluster.local:8000/health
```

### **Secretos no se aplican**
```bash
# Ver si el secret existe
kubectl get secret vocational-test-secrets -n vocational-test

# Verificar que el deployment referencia el secret
kubectl get deployment vocational-test -n vocational-test -o yaml | grep -A 10 "secretRef"

# Si falta, crear manualmente (ver sección de secrets)

# Forzar redeploy
kubectl rollout restart deployment/vocational-test -n vocational-test
```

---

## 📈 Escalado Futuro

Para agregar más proyectos:

1. **Crear directorio** `New_Project/` con YAMLs similares
2. **Actualizar IngressRoute** en `traefik/ingressroute.yaml`:
   ```yaml
   - match: "Host(`new-project.ikigais.app`)"
     services:
     - name: new-project
       port: 8080
   ```
3. **Push a main** → Traefik se actualiza automáticamente
4. **Sin downtime** ✨

---

## 🆘 Soporte

### **Reporte de Errores**
```bash
# Generar bugreport
kubectl cluster-info dump --output-directory=/tmp/k3s-debug

# Ver eventos recientes
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

### **Rollback Rápido**
```bash
# Si algo falla con Traefik
kubectl rollout undo deployment/traefik -n traefik

# Si algo falla con Vocational Test
kubectl rollout undo deployment/vocational-test -n vocational-test

# Ver historial
kubectl rollout history deployment/vocational-test -n vocational-test
```

---

## 📞 Contacto & Notas

- **Repo**: `https://github.com/gabrielwyp/K3S-Infra`
- **Cluster**: K3S en OCI, VM con IP pública
- **LB Externo**: OCI Load Balancer → Puerto 80 en VM
- **Dominio**: `ikigais.app` (apunta al LB)

---

**Last Updated**: 26 Febrero 2026  
**Maintainer**: Gabriel WP  
**Status**: ✅ Listo para producción
