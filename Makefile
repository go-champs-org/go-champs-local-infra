start:
	docker-compose -f docker-compose.rabbitmq.yml up -d

restart:
	docker-compose -f docker-compose.rabbitmq.yml down
	docker volume rm shared-rabbitmq-data
	docker-compose -f docker-compose.rabbitmq.yml up -d