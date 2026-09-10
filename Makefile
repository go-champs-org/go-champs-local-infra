start:
	docker-compose -f docker-compose.rabbitmq.yml up -d
	$(MAKE) apply-definitions

restart:
	docker-compose -f docker-compose.rabbitmq.yml down
	docker volume rm shared-rabbitmq-data
	docker-compose -f docker-compose.rabbitmq.yml up -d
	$(MAKE) apply-definitions

# Applies rabbitmq/definitions.json through the management API. Defaults to the
# local broker; point RABBIT_MQ_MANAGEMENT_URL / RABBIT_MQ_USERNAME /
# RABBIT_MQ_PASSWORD at a remote broker to apply there.
apply-definitions:
	./rabbitmq/apply-definitions.sh

.PHONY: start restart apply-definitions
