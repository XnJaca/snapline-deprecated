# Snapline

> [!WARNING]
> **Proyecto deprecado el 2026-09-23.** Se congela y se rearranca desde cero con
> otro enfoque de diseño y de flujos. No se abandona la idea, se abandona esta
> construcción.
>
> El motivo está en [`docs/DECISIONES.md`](docs/DECISIONES.md), con qué rescatar
> y qué hacer distinto. El modelo de dominio, los ADRs y la evidencia del brief
> siguen valiendo; el recorrido de pantallas es lo que no funcionó.


> Nombre en revisión. Ver `docs/NOMBRE.md` antes de registrar bundle ID o dominio.

El software de gestión para el contratista que no tiene oficina — y que termina el ciclo publicando la obra terminada en su web y sus redes.

## La apuesta

Dos cosas a la vez. Ninguna funciona sola:

1. **Se usa sin entrenamiento.** William paga QuickBooks y estima a mano igual, porque aprenderlo cuesta más que hacerlo mal. Si nuestra app necesita tutorial, ya perdimos.
2. **La foto termina publicada.** Es el único frente que le produce dinero en vez de ahorrarle tiempo.

## El ciclo

El trabajador toma la foto en sitio y ya viene etiquetada por proyecto, cliente y servicio. William aprueba qué se muestra. De ahí sale, sin intermediario, lo que se publica en su web — y el material de redes, que hoy hay que pedirle por WhatsApp.

El cliente ve su avance en un link, y ahí mismo se le ofrece el siguiente servicio. El cliente que ya pagó una obra es el lead más barato que existe.

## Los cinco frentes

| Frente | Qué resuelve |
|---|---|
| **Administrativo** | Proyectos, clientes, cuadrillas, catálogo de servicios, estimados y facturas |
| **Trabajadores en sitio** | Marcar entrada con geocerca y foto, capturar fotos del proyecto — sin señal |
| **Cliente** | Ver avance por link, y ofertas de otros servicios |
| **Reportes** | Timesheets para el contador, costo real por proyecto |
| **Publicidad** | Publicar a su web con un botón, antes/después, reseñas |

Detalle completo en **`docs/product/vision.md`**. Modelo de datos en **`docs/domain/`**.

## Qué NO es

- No calcula nómina. Entrega timesheets aprobados; el contador hace el payroll.
- No hace tracking continuo de ubicación. Solo el punto de entrada y salida.
- No hace inventario, compras ni órdenes de cambio.

## Stack

| Capa | Tecnología |
|---|---|
| Backend | NestJS + PostgreSQL |
| Móvil | Flutter (iOS + Android) |
| Admin web | Angular |
| Sitio público | Astro consumiendo el mismo API |

Fotos en Backblaze B2. Cuentas de App Store y Google Play ya disponibles.

## Estructura

```
snapline/
├── apps/
│   ├── api/       NestJS + PostgreSQL
│   ├── web/       Angular
│   ├── mobile/    Flutter (fuera del workspace de pnpm)
│   └── site/      Astro
├── packages/
│   └── contracts/ Tipos generados desde openapi.json
├── docs/          Decisiones y contexto
└── openapi.json   Contrato: fuente única de los tres clientes
```

Monorepo pnpm + Turborepo. Flutter vive adentro pero fuera del workspace: pub y
pnpm no se mezclan. Ver [ADR-0007](docs/adr/0007-openapi-como-contrato/README.md).

## Requisitos no negociables

**Funcionar sin señal.** Obras sin cobertura, sótanos, techos. Marcar entrada nunca puede fallar: sin red, sin GPS o sin cámara se registra igual con lo que haya. Un trabajador que no puede fichar deja de usar la app el primer día.

**El esquema se define completo antes de la primera migración.** Aunque las pantallas se entreguen por partes. Migrar con datos reales adentro cuesta cinco veces más.

**Mobile-first en todo.** El usuario está parado en un techo, no sentado en un escritorio.

## Contexto

- Design partner: **William Ferman** (Professional Construction LLC, Maryland). Usa la app gratis durante el desarrollo.
- Prototipo comprometido para la **semana del 2026-08-10**.
- Brief completo del producto: `docs/product/brief.md` (interno, fuera de git).

## Antes de escribir código

Leer **`docs/DECISIONES.md`**: arquitectura, orden de construcción, estado comercial y pendientes que no se pueden olvidar.

## Levantar el API

```bash
pnpm install
cd apps/api && cp .env.example .env
pnpm db:up && pnpm migration:run && pnpm seed
pnpm dev          # http://localhost:3000/api · docs en /api/docs
```

## Estado

Alcance reestructurado el 2026-08-08 tras la reunión con William.

`apps/api` está operativo: esquema completo, la mayoría de los módulos y tests.
`apps/mobile` con scaffold. `apps/web` y `apps/site` sin arrancar.

**El detalle vive en `.claude/CLAUDE.md` (sección Estado) — es la única fuente.**
No se repite acá para que no queden dos versiones que se contradicen.
