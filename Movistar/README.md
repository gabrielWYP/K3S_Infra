# Reto Movistar en K3S

La aplicación usa dos pods: `reto-movistar-front` publica la SPA mediante
Nginx y `reto-movistar-back` ejecuta FastAPI y los tres agentes. Traefik apunta
únicamente al frontend, que resuelve el backend por DNS interno.

Ambas imágenes usan el mismo tag inmutable `main-<sha>`:

- `ghcr.io/gabrielwyp/reto-movistar-front`
- `ghcr.io/gabrielwyp/reto-movistar-back`

Durante la primera migración, el workflow conserva el Deployment y Service
legacy hasta completar ambos rollouts y sus smoke tests. Si falla, restaura el
IngressRoute hacia el servicio anterior.
