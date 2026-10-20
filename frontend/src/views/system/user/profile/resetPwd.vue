<template>
  <el-form ref="pwdRef" :model="user" :rules="rules" label-width="80px">
    <el-form-item :label="$tt('旧密码')" prop="oldPassword">
      <el-input v-model="user.oldPassword" :placeholder="$tt('请输入旧密码')" type="password" show-password />
    </el-form-item>
    <el-form-item :label="$tt('新密码')" prop="newPassword">
      <el-input v-model="user.newPassword" :placeholder="$tt('请输入新密码')" type="password" show-password />
    </el-form-item>
    <el-form-item :label="$tt('确认密码')" prop="confirmPassword">
      <el-input v-model="user.confirmPassword" :placeholder="$tt('请确认新密码')" type="password" show-password />
    </el-form-item>
    <el-form-item>
      <el-button type="primary" @click="submit">{{ $tt('保存') }}</el-button>
      <el-button type="danger" @click="close">{{ $tt('关闭') }}</el-button>
    </el-form-item>
  </el-form>
</template>

<script setup lang="ts">
import { tt } from '@/utils/i18n';
import { updateUserPwd } from '@/api/system/user';
import type { ResetPwdForm } from '@/api/system/user/types';

const { proxy } = getCurrentInstance() as ComponentInternalInstance;
const pwdRef = ref<ElFormInstance>();
const user = ref<ResetPwdForm>({
  oldPassword: '',
  newPassword: '',
  confirmPassword: ''
});

const equalToPassword = (rule: any, value: string, callback: any) => {
  if (user.value.newPassword !== value) {
    callback(new Error(tt('两次输入的密码不一致')));
  } else {
    callback();
  }
};
const rules = ref({
  oldPassword: [{ required: true, message: tt('旧密码不能为空'), trigger: 'blur' }],
  newPassword: [
    { required: true, message: tt('新密码不能为空'), trigger: 'blur' },
    {
      min: 6,
      max: 20,
      message: tt('长度在 6 到 20 个字符'),
      trigger: 'blur'
    },
    { pattern: /^[^<>"'|\\]+$/, message: tt('不能包含非法字符：< > " \' \\ |'), trigger: 'blur' }
  ],
  confirmPassword: [
    { required: true, message: tt('确认密码不能为空'), trigger: 'blur' },
    {
      required: true,
      validator: equalToPassword,
      trigger: 'blur'
    }
  ]
});

/** 提交按钮 */
const submit = () => {
  pwdRef.value?.validate(async (valid: boolean) => {
    if (valid) {
      await updateUserPwd(user.value.oldPassword, user.value.newPassword);
      proxy?.$modal.msgSuccess(tt('修改成功'));
    }
  });
};
/** 关闭按钮 */
const close = () => {
  proxy?.$tab.closePage();
};
</script>
