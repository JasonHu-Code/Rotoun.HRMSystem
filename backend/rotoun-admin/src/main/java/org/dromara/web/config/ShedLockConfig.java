package org.dromara.web.config;

import net.javacrumbs.shedlock.core.LockProvider;
import net.javacrumbs.shedlock.provider.redis.spring.RedisLockProvider;
import net.javacrumbs.shedlock.spring.annotation.EnableSchedulerLock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * 定时任务分布式锁配置。
 *
 * <p>本项目不启用底座自带的 SnailJob，改用 Spring Task + ShedLock。
 * 锁存放在 Redis，保证多实例部署时同一任务同一时刻只执行一次。
 *
 * <p>为什么不用 SnailJob：本项目只有 4 类定时任务（考勤日结果、到期预警、
 * 打卡拉取、月结重算），302 人单实例部署，没必要额外维护一个调度中心服务。
 */
@Configuration
@EnableScheduling
@EnableSchedulerLock(defaultLockAtMostFor = "10m")
public class ShedLockConfig {

    @Bean
    public LockProvider lockProvider(RedisConnectionFactory connectionFactory) {
        // environment 会拼进 Redis key，避免与其他系统共用 Redis 时锁冲突
        return new RedisLockProvider(connectionFactory, "hr");
    }
}
