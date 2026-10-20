<template>
  <div class="p-2">
    <el-row :gutter="10">
      <el-col :span="24" class="card-box">
        <el-card shadow="hover">
          <template #header>
            <Monitor style="width: 1em; height: 1em; vertical-align: middle" />
            <span style="vertical-align: middle">{{ $tt('基本信息') }}</span>
          </template>

          <div class="el-table el-table--enable-row-hover el-table--medium">
            <table style="width: 100%">
              <tbody>
                <tr>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('Redis版本') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">{{ cache.info.redis_version }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('运行模式') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">{{ cache.info.redis_mode === 'standalone' ? $tt('单机') : $tt('集群') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('端口') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">{{ cache.info.tcp_port }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('客户端数') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">{{ cache.info.connected_clients }}</div>
                  </td>
                </tr>
                <tr>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('运行时间(天)') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">{{ cache.info.uptime_in_days }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('使用内存') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">{{ cache.info.used_memory_human }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('使用CPU') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">{{ parseFloat(cache.info.used_cpu_user_children).toFixed(2) }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('内存配置') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">{{ cache.info.maxmemory_human }}</div>
                  </td>
                </tr>
                <tr>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('AOF是否开启') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">{{ cache.info.aof_enabled === '0' ? $tt('否') : $tt('是') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('RDB是否成功') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">{{ cache.info.rdb_last_bgsave_status }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('Key数量') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.dbSize" class="cell">{{ cache.dbSize }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div class="cell">{{ $tt('网络入口/出口') }}</div>
                  </td>
                  <td class="el-table__cell is-leaf">
                    <div v-if="cache.info" class="cell">
                      {{ cache.info.instantaneous_input_kbps }}kps/{{ cache.info.instantaneous_output_kbps }}kps
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </el-card>
      </el-col>

      <el-col :span="12" class="card-box">
        <el-card shadow="hover">
          <template #header>
            <PieChart style="width: 1em; height: 1em; vertical-align: middle" />
            <span style="vertical-align: middle">{{ $tt('命令统计') }}</span>
          </template>
          <div class="el-table el-table--enable-row-hover el-table--medium">
            <div ref="commandstats" style="height: 420px" />
          </div>
        </el-card>
      </el-col>

      <el-col :span="12" class="card-box">
        <el-card shadow="hover">
          <template #header>
            <Odometer style="width: 1em; height: 1em; vertical-align: middle" /> <span style="vertical-align: middle">{{ $tt('内存信息') }}</span>
          </template>
          <div class="el-table el-table--enable-row-hover el-table--medium">
            <div ref="usedmemory" style="height: 420px" />
          </div>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<script setup name="Cache" lang="ts">
import { tt } from '@/utils/i18n';
import { getCache } from '@/api/monitor/cache';
import * as echarts from 'echarts';
import { CacheVO } from '@/api/monitor/cache/types';

const cache = ref<Partial<CacheVO>>({});
const commandstats = ref();
const usedmemory = ref();
const { proxy } = getCurrentInstance() as ComponentInternalInstance;

const getList = async () => {
  proxy?.$modal.loading(tt('正在加载缓存监控数据，请稍候！'));
  const res = await getCache();
  proxy?.$modal.closeLoading();
  cache.value = res.data;
  const commandstatsIntance = echarts.init(commandstats.value, 'macarons');
  commandstatsIntance.setOption({
    tooltip: {
      trigger: 'item',
      formatter: '{a} <br/>{b} : {c} ({d}%)'
    },
    series: [
      {
        name: tt('命令'),
        type: 'pie',
        roseType: 'radius',
        radius: [15, 95],
        center: ['50%', '38%'],
        data: res.data.commandStats,
        animationEasing: 'cubicInOut',
        animationDuration: 1000
      }
    ]
  });
  const usedmemoryInstance = echarts.init(usedmemory.value, 'macarons');
  usedmemoryInstance.setOption({
    tooltip: {
      formatter: '{b} <br/>{a} : ' + cache.value.info.used_memory_human
    },
    series: [
      {
        name: tt('峰值'),
        type: 'gauge',
        min: 0,
        max: 1000,
        detail: {
          formatter: cache.value.info.used_memory_human
        },
        data: [
          {
            value: parseFloat(cache.value.info.used_memory_human),
            name: tt('内存消耗')
          }
        ]
      }
    ]
  });
  window.addEventListener('resize', () => {
    commandstatsIntance.resize();
    usedmemoryInstance.resize();
  });
};

onMounted(() => {
  getList();
});
</script>
