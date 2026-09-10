# go-champs-local-infra

Shared infrastructure for local development, and the source of truth for the
RabbitMQ topology every environment runs on.

## Quickstart

```
make start     # bring the broker up and apply the topology
make restart   # wipe the volume and rebuild from scratch
```

The broker joins the external network `go-champs-shared-network`, which the
application devcontainers attach to. Create it once if it doesn't exist:

```
docker network create go-champs-shared-network
```

Management UI: http://localhost:15672 (`local_user` / `local_pass`).

## The RabbitMQ topology

`rabbitmq/definitions.json` describes every exchange, queue, binding and
argument the platform uses. It is the single source of truth, and it has two
different consumers.

### The applications, in every real environment

`go_champs_api`, `go_champs_scoreboard`, `lockerroom-api` and `play_sync` each
carry a versioned copy of this file. During their deploy — release phase on
Heroku, entrypoint on the play_sync VM — they declare the whole topology over
AMQP, and at boot they passively verify the objects they use, refusing to start
when something is missing.

No manual step, and no management credentials in any application.

### `make apply-definitions`, locally only

Applies the same file through the management API. This is a development
convenience so a fresh broker is usable before any app has been deployed against
it. It is **not** the deploy path, for two reasons, both verified against a real
broker:

- **Definitions import needs the `administrator` tag** — on the cluster endpoint
  and the vhost-scoped one alike. `management`, and `management,policymaker`,
  both get `401 not_authorised`. A CloudAMQP shared-plan user does not have it.
- **Import never verifies anything.** Importing a queue whose arguments differ
  from the broker's, or an exchange with `durable` flipped, returns **HTTP 204
  success** while the broker silently keeps its old state. "Definitions applied"
  does not mean "the broker matches the file".

An AMQP declare has neither problem: it needs only `configure` permission on the
vhost, and a mismatched argument returns `PRECONDITION_FAILED` — which fails the
deploy, loudly, at the right moment.

To point the script at another broker:

```
RABBIT_MQ_MANAGEMENT_URL=https://<host> \
RABBIT_MQ_USERNAME=<user> \
RABBIT_MQ_PASSWORD=<pass> \
RABBIT_MQ_VHOST=<vhost> \
./rabbitmq/apply-definitions.sh
```

## Changing the topology

1. Edit `rabbitmq/definitions.json` here.
2. Re-vendor the copy in each application repository. CI in those repositories
   compares its copy against this one and fails the build when they diverge.
3. Deploy.

Two rules that are not obvious:

**The file must describe production exactly.** Since the applications apply it
with AMQP declares, any divergence from what the broker already holds fails the
deploy. Fixing something "in passing" while editing this file breaks every
deploy that follows. Changing a property of an object that already exists is a
migration, not an edit — see [Exchange durability](#exchange-durability) for the
one case that has one.

**Order matters, differently per direction.** Additions can go out ahead of the
applications that need them. Removals go last, after every application has
stopped referencing the object — and note that removing an object here does not
delete it from a broker. Import is a merge, not a sync; deletion stays manual, on
purpose.

There is no `vhost` key on any object. The applications get the vhost from their
own connection, and on CloudAMQP it is not `/`.

## Exchange durability

Every exchange here is durable. `game-events` and `dead-letter-exchange` were
not always: `go_champs_scoreboard` declared both without `durable: true`, so a
broker restart dropped them and every binding on them, and the next application
boot quietly recreated them. That silent repair is what kept production working,
and it stopped being available once the applications began asserting the
topology instead of declaring it at boot.

Making them durable means deleting and recreating them, which drops their
bindings. `mix rabbitmq.migrate.exchange_durability` in the scoreboard does
exactly that during the release phase, and the declare that follows restores the
bindings from this file. It only ever deletes an exchange it has confirmed is
non-durable, which is an object the broker would have discarded on its own at
the next restart.

Durable exchanges and durable queues still do not make a *message* survive a
restart — that needs `persistent: true` on publish, which the publishers do not
all set yet. Tracked separately.
