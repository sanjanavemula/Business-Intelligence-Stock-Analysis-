package com.stockstream.dashboard;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.config.annotation.*;

import java.time.Instant;
import java.util.List;
import java.util.Map;

/**
 * WebSocket configuration using STOMP over SockJS.
 * Clients subscribe to /topic/ticks and /topic/stats.
 */
@Configuration
@EnableWebSocketMessageBroker
class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // SockJS endpoint — JS clients connect to ws://localhost:8080/ws
        registry.addEndpoint("/ws").withSockJS();
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        registry.enableSimpleBroker("/topic");
        registry.setApplicationDestinationPrefixes("/app");
    }
}

/**
 * Scheduled broadcaster — pushes live tick data to all WebSocket subscribers
 * every 3 seconds.
 */
@Component
class WebSocketBroadcaster {

    private static final Logger log = LoggerFactory.getLogger(WebSocketBroadcaster.class);

    @Autowired private SimpMessagingTemplate messaging;
    @Autowired private StockRepository       repo;

    @Scheduled(fixedDelay = 3000)
    public void broadcastTicks() {
        try {
            List<StockLatest> latest = repo.findAllLatest();
            messaging.convertAndSend("/topic/ticks", Map.of(
                "data", latest,
                "ts",   Instant.now().toString()
            ));
        } catch (Exception e) {
            log.debug("Broadcast skipped (DB may be empty): {}", e.getMessage());
        }
    }

    @Scheduled(fixedDelay = 5000)
    public void broadcastStats() {
        try {
            messaging.convertAndSend("/topic/stats", repo.getPipelineStats());
        } catch (Exception e) {
            log.debug("Stats broadcast skipped: {}", e.getMessage());
        }
    }
}
