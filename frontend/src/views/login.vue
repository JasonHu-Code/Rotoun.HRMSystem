<template>
  <div class="login">
    <!-- 动态背景层：原图推拉 + 光带扫过 + 流动光斑 + 漂浮微尘，纯 CSS 实现，不引第三方库 -->
    <div class="login-bg" aria-hidden="true">
      <div class="bg-photo"></div>
      <div class="sweep sweep-1"></div>
      <div class="sweep sweep-2"></div>
      <div class="glow glow-1"></div>
      <div class="glow glow-2"></div>
      <div class="glow glow-3"></div>
      <div class="particles"></div>
    </div>
    <el-form ref="loginRef" :model="loginForm" :rules="loginRules" class="login-form">
      <div class="title-box">
        <div class="title-brand">
          <img src="@/assets/logo/logo.png" class="login-logo" alt="logo" />
          <h3 class="title">{{ $tt(title) }}</h3>
        </div>
        <lang-select />
      </div>
      <el-form-item v-if="tenantEnabled" prop="tenantId">
        <el-select v-model="loginForm.tenantId" filterable :placeholder="proxy.$t('login.selectPlaceholder')" style="width: 100%">
          <el-option v-for="item in tenantList" :key="item.tenantId" :label="item.companyName" :value="item.tenantId"></el-option>
          <template #prefix><svg-icon icon-class="company" class="el-input__icon input-icon" /></template>
        </el-select>
      </el-form-item>
      <el-form-item prop="username">
        <el-input v-model="loginForm.username" type="text" size="large" auto-complete="off" :placeholder="proxy.$t('login.username')">
          <template #prefix><svg-icon icon-class="user" class="el-input__icon input-icon" /></template>
        </el-input>
      </el-form-item>
      <el-form-item prop="password">
        <el-input
          v-model="loginForm.password"
          type="password"
          size="large"
          auto-complete="off"
          :placeholder="proxy.$t('login.password')"
          @keyup.enter="handleLogin"
        >
          <template #prefix><svg-icon icon-class="password" class="el-input__icon input-icon" /></template>
        </el-input>
      </el-form-item>
      <el-form-item v-if="captchaEnabled" prop="code">
        <el-input
          v-model="loginForm.code"
          size="large"
          auto-complete="off"
          :placeholder="proxy.$t('login.code')"
          style="width: 63%"
          @keyup.enter="handleLogin"
        >
          <template #prefix><svg-icon icon-class="validCode" class="el-input__icon input-icon" /></template>
        </el-input>
        <div class="login-code">
          <img :src="codeUrl" class="login-code-img" @click="getCode" />
        </div>
      </el-form-item>
      <el-checkbox v-model="loginForm.rememberMe" style="margin: 0 0 25px 0">{{ proxy.$t('login.rememberPassword') }}</el-checkbox>
      <el-form-item style="float: right">
        <el-button circle :title="proxy.$t('login.social.wechat')" @click="doSocialLogin('wechat')">
          <svg-icon icon-class="wechat" />
        </el-button>
        <el-button circle :title="proxy.$t('login.social.maxkey')" @click="doSocialLogin('maxkey')">
          <svg-icon icon-class="maxkey" />
        </el-button>
        <el-button circle :title="proxy.$t('login.social.topiam')" @click="doSocialLogin('topiam')">
          <svg-icon icon-class="topiam" />
        </el-button>
        <el-button circle :title="proxy.$t('login.social.gitee')" @click="doSocialLogin('gitee')">
          <svg-icon icon-class="gitee" />
        </el-button>
        <el-button circle :title="proxy.$t('login.social.github')" @click="doSocialLogin('github')">
          <svg-icon icon-class="github" />
        </el-button>
      </el-form-item>
      <el-form-item style="width: 100%">
        <el-button :loading="loading" size="large" type="primary" style="width: 100%" @click.prevent="handleLogin">
          <span v-if="!loading">{{ proxy.$t('login.login') }}</span>
          <span v-else>{{ proxy.$t('login.logging') }}</span>
        </el-button>
        <div v-if="register" style="float: right">
          <router-link class="link-type" :to="'/register'">{{ proxy.$t('login.switchRegisterPage') }}</router-link>
        </div>
      </el-form-item>
    </el-form>
    <!--  底部  -->
    <div class="el-login-footer">
      <span>© 2026 瑞堂塑料集团 Rotoun Group. All Rights Reserved.</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { getCodeImg, getTenantList } from '@/api/login';
import { authRouterUrl } from '@/api/system/social/auth';
import { useUserStore } from '@/store/modules/user';
import { LoginData, TenantVO } from '@/api/types';
import { to } from 'await-to-js';
import { HttpStatus } from '@/enums/RespEnum';
import { useI18n } from 'vue-i18n';

const { proxy } = getCurrentInstance() as ComponentInternalInstance;

const title = import.meta.env.VITE_APP_TITLE;
const userStore = useUserStore();
const router = useRouter();
const { t } = useI18n();

const loginForm = ref<LoginData>({
  tenantId: '000000',
  username: 'admin',
  password: 'admin123',
  rememberMe: false,
  code: '',
  uuid: ''
} as LoginData);

const loginRules: ElFormRules = {
  tenantId: [{ required: true, trigger: 'blur', message: t('login.rule.tenantId.required') }],
  username: [{ required: true, trigger: 'blur', message: t('login.rule.username.required') }],
  password: [{ required: true, trigger: 'blur', message: t('login.rule.password.required') }],
  code: [{ required: true, trigger: 'change', message: t('login.rule.code.required') }]
};

const codeUrl = ref('');
const loading = ref(false);
// 验证码开关
const captchaEnabled = ref(true);
// 租户开关
const tenantEnabled = ref(true);

// 注册开关
const register = ref(false);
const redirect = ref('/');
const loginRef = ref<ElFormInstance>();
// 租户列表
const tenantList = ref<TenantVO[]>([]);

watch(
  () => router.currentRoute.value,
  (newRoute: any) => {
    redirect.value = newRoute.query && newRoute.query.redirect && decodeURIComponent(newRoute.query.redirect);
  },
  { immediate: true }
);

const handleLogin = () => {
  loginRef.value?.validate(async (valid: boolean, fields: any) => {
    if (valid) {
      loading.value = true;
      // 勾选了需要记住密码设置在 localStorage 中设置记住用户名和密码
      if (loginForm.value.rememberMe) {
        localStorage.setItem('tenantId', String(loginForm.value.tenantId));
        localStorage.setItem('username', String(loginForm.value.username));
        localStorage.setItem('password', String(loginForm.value.password));
        localStorage.setItem('rememberMe', String(loginForm.value.rememberMe));
      } else {
        // 否则移除
        localStorage.removeItem('tenantId');
        localStorage.removeItem('username');
        localStorage.removeItem('password');
        localStorage.removeItem('rememberMe');
      }
      // 调用action的登录方法
      const [err] = await to(userStore.login(loginForm.value));
      if (!err) {
        const redirectUrl = redirect.value || '/';
        await router.push(redirectUrl);
        loading.value = false;
      } else {
        loading.value = false;
        // 重新获取验证码
        if (captchaEnabled.value) {
          await getCode();
        }
      }
    } else {
      console.log('error submit!', fields);
    }
  });
};

/**
 * 获取验证码
 */
const getCode = async () => {
  const res = await getCodeImg();
  const { data } = res;
  captchaEnabled.value = data.captchaEnabled === undefined ? true : data.captchaEnabled;
  if (captchaEnabled.value) {
    // 刷新验证码时清空输入框
    loginForm.value.code = '';
    codeUrl.value = 'data:image/gif;base64,' + data.img;
    loginForm.value.uuid = data.uuid;
  }
};

const getLoginData = () => {
  const tenantId = localStorage.getItem('tenantId');
  const username = localStorage.getItem('username');
  const password = localStorage.getItem('password');
  const rememberMe = localStorage.getItem('rememberMe');
  loginForm.value = {
    tenantId: tenantId === null ? String(loginForm.value.tenantId) : tenantId,
    username: username === null ? String(loginForm.value.username) : username,
    password: password === null ? String(loginForm.value.password) : String(password),
    rememberMe: rememberMe === null ? false : Boolean(rememberMe)
  } as LoginData;
};

/**
 * 获取租户列表
 */
const initTenantList = async () => {
  const { data } = await getTenantList(false);
  tenantEnabled.value = data.tenantEnabled === undefined ? true : data.tenantEnabled;
  if (tenantEnabled.value) {
    tenantList.value = data.voList;
    if (tenantList.value != null && tenantList.value.length !== 0) {
      loginForm.value.tenantId = tenantList.value[0].tenantId;
    }
  }
};

/**
 * 第三方登录
 * @param type
 */
const doSocialLogin = (type: string) => {
  authRouterUrl(type, loginForm.value.tenantId).then((res: any) => {
    if (res.code === HttpStatus.SUCCESS) {
      // 获取授权地址跳转
      window.location.href = res.data;
    } else {
      ElMessage.error(res.msg);
    }
  });
};

onMounted(() => {
  getCode();
  initTenantList();
  getLoginData();
});
</script>

<style lang="scss" scoped>
.login {
  position: relative;
  display: flex;
  justify-content: center;
  align-items: center;
  height: 100%;
  overflow: hidden;
  // 兜底底色，避免背景图解码前闪白
  background: #2f7fe8;
}

// 背景容器只负责裁切与定位，自身不做动画：
// 若让父级缩放，子元素的位移会被叠加放大，调起来互相干扰
.login-bg {
  position: absolute;
  inset: 0;
  z-index: 0;
  overflow: hidden;
  pointer-events: none;
}

// 底图单独一层做推拉。
// 幅度和速度是关键：1.02 -> 1.14 / 24s 才有方向感；
// 之前的 1.03 -> 1.12 / 42s 属于"匀速慢缩放"，人眼几乎没有参照物，看起来就是静态图。
.bg-photo {
  position: absolute;
  inset: 0;
  background-image: url('../assets/images/login-background.jpg');
  background-size: cover;
  background-position: center;
  animation: bg-drift 24s ease-in-out infinite alternate;
  will-change: transform;
}

// 斜向光带扫过：整屏最容易被感知的动效，也是让背景"活"起来的主力
.sweep {
  position: absolute;
  top: -25%;
  left: -40vw;
  width: 32vw;
  height: 150%;
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 0) 0%,
    rgba(255, 255, 255, 0.16) 42%,
    rgba(255, 255, 255, 0.3) 52%,
    rgba(255, 255, 255, 0) 100%
  );
  filter: blur(24px);
  animation: sweep-x 13s linear infinite;
}

// 第二条更细更慢、错开相位，避免节奏过于机械
.sweep-2 {
  width: 18vw;
  opacity: 0.65;
  animation-duration: 19s;
  animation-delay: -7s;
}

.glow {
  position: absolute;
  border-radius: 50%;
  filter: blur(64px);
  pointer-events: none;
}

// 注意：原设计用了 mix-blend-mode: screen，但背景本身是高明度天蓝，
// screen 叠上去几乎等于没有——这是"看不出变化"的第二个原因。改为普通混合 + 控制 alpha。
.glow-1 {
  width: 46vw;
  height: 46vw;
  left: -14vw;
  top: -16vw;
  background: radial-gradient(circle, rgba(255, 255, 255, 0.5) 0%, rgba(160, 215, 255, 0) 70%);
  animation: glow-drift-a 14s ease-in-out infinite;
}

.glow-2 {
  width: 40vw;
  height: 40vw;
  right: -12vw;
  bottom: -14vw;
  background: radial-gradient(circle, rgba(255, 170, 110, 0.38) 0%, rgba(255, 170, 110, 0) 72%);
  animation: glow-drift-b 17s ease-in-out infinite;
}

.glow-3 {
  width: 32vw;
  height: 32vw;
  left: 40%;
  top: 4%;
  background: radial-gradient(circle, rgba(120, 190, 255, 0.45) 0%, rgba(120, 190, 255, 0) 72%);
  animation: glow-drift-c 12s ease-in-out infinite;
}

.particles {
  position: absolute;
  inset: -30%;
  background-image: radial-gradient(circle, rgba(255, 255, 255, 0.85) 1.6px, transparent 2px);
  background-size: 96px 96px;
  opacity: 0.3;
  animation: particle-rise 26s linear infinite;
}

@keyframes bg-drift {
  from {
    transform: scale(1.02) translate3d(0, 0, 0);
  }
  to {
    transform: scale(1.14) translate3d(-2.6%, -2%, 0);
  }
}

@keyframes sweep-x {
  from {
    transform: translate3d(0, 0, 0) rotate(16deg);
  }
  to {
    transform: translate3d(160vw, 0, 0) rotate(16deg);
  }
}

@keyframes glow-drift-a {
  0%,
  100% {
    transform: translate3d(0, 0, 0) scale(1);
  }
  50% {
    transform: translate3d(11vw, 7vh, 0) scale(1.18);
  }
}

@keyframes glow-drift-b {
  0%,
  100% {
    transform: translate3d(0, 0, 0) scale(1.08);
  }
  50% {
    transform: translate3d(-9vw, -8vh, 0) scale(0.9);
  }
}

@keyframes glow-drift-c {
  0%,
  100% {
    transform: translate3d(0, 0, 0);
  }
  50% {
    transform: translate3d(-8vw, 10vh, 0);
  }
}

// 位移量取贴图尺寸的整数倍才能无缝衔接：96 × 10 = 960
@keyframes particle-rise {
  from {
    background-position: 0 0;
  }
  to {
    background-position: -96px -960px;
  }
}

@keyframes card-in {
  from {
    opacity: 0;
    transform: translateY(18px) scale(0.985);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

@keyframes logo-breathe {
  0%,
  100% {
    transform: translateY(0);
  }
  50% {
    transform: translateY(-3px);
  }
}

// 尊重系统的"减少动态效果"设置：无障碍要求，也避免低配机器掉帧
@media (prefers-reduced-motion: reduce) {
  .bg-photo,
  .sweep,
  .glow,
  .particles,
  .login-form,
  .title-brand .login-logo {
    animation: none !important;
  }

  .sweep {
    opacity: 0;
  }
}

.title-box {
  display: flex;
  align-items: center;
  gap: 8px;

  // 品牌区：logo + 系统名整体居中，语言切换靠右
  .title-brand {
    display: flex;
    align-items: center;
    gap: 10px;
    margin: 0 auto 26px auto;
  }

  .login-logo {
    width: 36px;
    height: 36px;
    flex: 0 0 auto;
    animation: logo-breathe 6s ease-in-out infinite;
  }

  .title {
    margin: 0;
    text-align: center;
    color: var(--el-text-color-primary);
    font-weight: 600;
    letter-spacing: 0.5px;
  }

  :deep(.lang-select--style) {
    line-height: 0;
    color: var(--el-text-color-secondary);
  }
}

.login-form {
  border-radius: var(--app-radius-lg);
  background: rgba(255, 255, 255, 0.94);
  border: 1px solid rgba(255, 255, 255, 0.5);
  width: min(420px, 90vw);
  padding: 32px 30px 12px 30px;
  z-index: 1;
  box-shadow: var(--app-shadow-lg);
  backdrop-filter: blur(6px);
  -webkit-backdrop-filter: blur(6px);
  animation: card-in 0.9s cubic-bezier(0.22, 1, 0.36, 1) both;
  .el-input {
    height: 40px;
    input {
      height: 40px;
    }
  }

  .input-icon {
    height: 39px;
    width: 14px;
    margin-left: 0px;
  }
}

.login-tip {
  font-size: 13px;
  text-align: center;
  color: #bfbfbf;
}

.login-form :deep(.el-input__wrapper) {
  background-color: rgba(255, 255, 255, 0.9);
}

.login-form :deep(.el-input__wrapper.is-focus) {
  box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.2);
}

.login-form :deep(.el-button--primary) {
  border-radius: var(--app-radius-md);
  box-shadow: 0 8px 20px rgba(59, 130, 246, 0.25);
}

.login-form :deep(.el-button.is-circle) {
  background: rgba(15, 23, 42, 0.04);
  border: 1px solid rgba(15, 23, 42, 0.08);
  color: var(--el-text-color-regular);
}

.login-form :deep(.el-button.is-circle:hover) {
  background: rgba(59, 130, 246, 0.1);
  border-color: rgba(59, 130, 246, 0.2);
}

.login-code {
  width: calc(37% - 10px);
  height: 40px;
  float: right;
  margin-left: 10px;
  box-sizing: border-box;
  border-radius: var(--app-radius-sm);
  overflow: hidden;
  background: rgba(255, 255, 255, 0.9);
  border: 1px solid var(--el-border-color-light);

  img {
    cursor: pointer;
    vertical-align: middle;
    display: block;
    width: 100%;
    height: 40px;
    object-fit: cover;
  }
}

.el-login-footer {
  height: auto;
  line-height: 1.6;
  position: fixed;
  bottom: 14px;
  width: 100%;
  text-align: center;
  color: rgba(255, 255, 255, 0.85);
  /* 背景是浅蓝色块，纯白字容易糊掉，加一层极淡投影把字从背景里"抬"起来 */
  text-shadow: 0 1px 2px rgba(0, 60, 120, 0.35);
  font-family: Arial, serif;
  font-size: 12px;
  letter-spacing: 1px;
  pointer-events: none;
}

.login-code-img {
  height: 40px;
  padding-left: 0;
}

:global(html.dark) {
  .login-form {
    background: rgba(17, 24, 39, 0.9);
    border-color: rgba(148, 163, 184, 0.2);
  }

  .login-form :deep(.el-input__wrapper) {
    background-color: rgba(17, 24, 39, 0.7);
  }

  .login-form :deep(.el-button.is-circle) {
    background: rgba(148, 163, 184, 0.12);
    border-color: rgba(148, 163, 184, 0.25);
    color: #e5e7eb;
  }

  .el-login-footer {
    color: rgba(226, 232, 240, 0.65);
  }
}
</style>
