package com.demo.gateway.filter;

import lombok.extern.slf4j.Slf4j;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.util.UUID;

@Slf4j
@Component
public class RequestTraceFilter implements GlobalFilter, Ordered {

    private static final String TRACE_ID_HEADER = "X-Trace-Id";
    private static final String START_TIME_HEADER = "X-Start-Time";

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String traceId = exchange.getRequest().getHeaders().getFirst(TRACE_ID_HEADER);
        if (traceId == null || traceId.isEmpty()) {
            traceId = UUID.randomUUID().toString().replace("-", "").substring(0, 16);
        }

        long startTime = System.currentTimeMillis();

        ServerHttpRequest request = exchange.getRequest().mutate()
                .header(TRACE_ID_HEADER, traceId)
                .header(START_TIME_HEADER, String.valueOf(startTime))
                .build();

        log.info("Gateway request: {} {} - traceId: {}",
                request.getMethod(), request.getPath(), traceId);

        return chain.filter(exchange.mutate().request(request).build())
                .then(Mono.fromRunnable(() -> {
                    long duration = System.currentTimeMillis() - startTime;
                    log.info("Gateway response: {} {} - status: {}, duration: {}ms, traceId: {}",
                            request.getMethod(), request.getPath(),
                            exchange.getResponse().getStatusCode(),
                            duration, traceId);
                }));
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }
}
