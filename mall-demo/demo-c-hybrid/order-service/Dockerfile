# ============================================
# Build Stage - Maven
# ============================================
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /app

COPY pom.xml .
RUN mvn dependency:go-offline -B

COPY src ./src
RUN mvn package -DskipTests -B

# ============================================
# Runtime Stage
# ============================================
FROM eclipse-temurin:17-jre-alpine

RUN apk add --no-cache ca-certificates tzdata curl
ENV TZ=Asia/Shanghai

WORKDIR /app

COPY --from=builder /app/target/*.jar app.jar

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
