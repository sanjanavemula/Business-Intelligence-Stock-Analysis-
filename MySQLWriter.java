# ── Server ────────────────────────────────────────────────
server.port=8080
spring.application.name=StockStream Dashboard

# ── MySQL DataSource ──────────────────────────────────────
spring.datasource.url=jdbc:mysql://localhost:3306/stockstream_ai?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
spring.datasource.username=stockuser
spring.datasource.password=StockPass@123
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# ── Connection pool ────────────────────────────────────────
spring.datasource.hikari.maximum-pool-size=10
spring.datasource.hikari.minimum-idle=2
spring.datasource.hikari.connection-timeout=20000
spring.datasource.hikari.idle-timeout=300000

# ── Thymeleaf ──────────────────────────────────────────────
spring.thymeleaf.cache=false
spring.thymeleaf.prefix=classpath:/templates/
spring.thymeleaf.suffix=.html

# ── Logging ────────────────────────────────────────────────
logging.level.com.stockstream=INFO
logging.level.org.springframework.web=WARN
logging.level.org.springframework.messaging=WARN
