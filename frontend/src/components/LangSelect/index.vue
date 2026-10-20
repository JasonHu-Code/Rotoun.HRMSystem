<template>
  <el-dropdown trigger="click" @command="handleLanguageChange">
    <div class="lang-select--style">
      <svg-icon icon-class="language" />
    </div>
    <template #dropdown>
      <el-dropdown-menu>
        <el-dropdown-item :disabled="appStore.language === 'zh_CN'" command="zh_CN">{{ $tt('中文') }}</el-dropdown-item>
        <el-dropdown-item :disabled="appStore.language === 'en_US'" command="en_US"> English </el-dropdown-item>
      </el-dropdown-menu>
    </template>
  </el-dropdown>
</template>

<script setup lang="ts">
import { tt } from '@/utils/i18n';
import { useI18n } from 'vue-i18n';
import { useAppStore } from '@/store/modules/app';
import SvgIcon from '@/components/SvgIcon/index.vue';

const appStore = useAppStore();
const { locale } = useI18n();

const handleLanguageChange = (lang: any) => {
  locale.value = lang;
  appStore.changeLanguage(lang);
  ElMessage.success(lang === 'zh_CN' ? tt('切换语言成功！') : 'Switch Language Successful!');
  // 菜单名来自数据库、部分文案在 setup 顶层只求值一次，响应式覆盖不全；
  // 语言切换是低频操作，整页重载最彻底，也避免半中半英的中间态
  setTimeout(() => window.location.reload(), 400);
};
</script>

<style lang="scss" scoped>
.lang-select--style {
  font-size: 18px;
  line-height: 50px;
}
</style>
