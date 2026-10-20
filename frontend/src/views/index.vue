<template>
  <div class="app-container">
    <el-card shadow="never">
      <div class="welcome">
        <h2>瑞堂人事管理系统</h2>
        <p>组织、员工、考勤、薪酬、假期一体化管理平台。</p>
        <el-descriptions :column="2" border>
          <el-descriptions-item label="系统版本">V0.1</el-descriptions-item>
          <el-descriptions-item label="技术底座">Spring Boot 3.5.16 / Vue 3.5</el-descriptions-item>
          <el-descriptions-item label="数据库">MySQL 8 · rt-hrms</el-descriptions-item>
          <el-descriptions-item label="认证">Sa-Token + JWT</el-descriptions-item>
        </el-descriptions>
      </div>
    </el-card>
  </div>
</template>

<style scoped>
.welcome {
  padding: 8px 4px;
}
.welcome h2 {
  margin: 0 0 8px;
  font-size: 22px;
  color: #1a1a1a;
}
.welcome p {
  margin: 0 0 20px;
  color: #666;
}
</style>
