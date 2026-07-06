# Multi-stage build for order-service
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
COPY order-service/pom.xml order-service/
RUN mvn dependency:go-offline -B -pl order-service -am || true
COPY order-service/src order-service/src
RUN mvn package -pl order-service -am -DskipTests -B

FROM eclipse-temurin:17-jre-alpine
LABEL maintainer="mall-demo"
WORKDIR /app

ENV OTEL_JAVA_AGENT_VERSION=1.32.0

RUN apk add --no-cache curl wget && \
    wget -q https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_JAVA_AGENT_VERSION}/opentelemetry-javaagent.jar -O /app/opentelemetry-javaagent.jar

COPY --from=builder /build/order-service/target/order-service.jar app.jar

ENV JAVA_OPTS="-Xms128m -Xmx256m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
ENV OTEL_SERVICE_NAME="order-service"
ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector.monitoring:4317"
ENV OTEL_JAVA_AUTO-ENABLED-INSTRUMENTATIONS="spring-boot,webmvc,jdbc,redis,kafka,apache-httpclient"

EXPOSE 8082

ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -javaagent:/app/opentelemetry-javaagent.jar -jar app.jar"]
