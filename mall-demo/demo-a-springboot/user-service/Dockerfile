# Multi-stage build for user-service
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
COPY user-service/pom.xml user-service/
RUN mvn dependency:go-offline -B -pl user-service -am || true
COPY user-service/src user-service/src
RUN mvn package -pl user-service -am -DskipTests -B

FROM eclipse-temurin:17-jre-alpine
LABEL maintainer="mall-demo"
WORKDIR /app

# OTel Java Agent
ENV OTEL_JAVA_AGENT_VERSION=1.32.0

RUN apk add --no-cache curl wget && \
    wget -q https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_JAVA_AGENT_VERSION}/opentelemetry-javaagent.jar -O /app/opentelemetry-javaagent.jar

COPY --from=builder /build/user-service/target/user-service.jar app.jar

# JVM memory settings - max 256MB
ENV JAVA_OPTS="-Xms128m -Xmx256m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
ENV OTEL_SERVICE_NAME="user-service"
ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector.monitoring:4317"
ENV OTEL_JAVA_AUTO-ENABLED-INSTRUMENTATIONS="spring-boot,webmvc,jdbc,redis"

EXPOSE 8081

ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -javaagent:/app/opentelemetry-javaagent.jar -jar app.jar"]
