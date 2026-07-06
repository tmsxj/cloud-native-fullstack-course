# Multi-stage build for api-gateway
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
COPY api-gateway/pom.xml api-gateway/
RUN mvn dependency:go-offline -B -pl api-gateway -am || true
COPY api-gateway/src api-gateway/src
RUN mvn package -pl api-gateway -am -DskipTests -B

FROM eclipse-temurin:17-jre-alpine
LABEL maintainer="mall-demo"
WORKDIR /app

ENV OTEL_JAVA_AGENT_VERSION=1.32.0

RUN apk add --no-cache curl wget && \
    wget -q https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_JAVA_AGENT_VERSION}/opentelemetry-javaagent.jar -O /app/opentelemetry-javaagent.jar

COPY --from=builder /build/api-gateway/target/api-gateway.jar app.jar

ENV JAVA_OPTS="-Xms128m -Xmx256m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
ENV OTEL_SERVICE_NAME="api-gateway"
ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector.monitoring:4317"
ENV OTEL_JAVA_AUTO-ENABLED-INSTRUMENTATIONS="spring-boot,gateway,netty"

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -javaagent:/app/opentelemetry-javaagent.jar -jar app.jar"]
