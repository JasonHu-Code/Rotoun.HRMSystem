<template>
  <el-form ref="userRef" :model="userForm" :rules="rules" label-width="80px">
    <el-form-item :label="$tt('用户昵称')" prop="nickName">
      <el-input v-model="userForm.nickName" maxlength="30" />
    </el-form-item>
    <el-form-item :label="$tt('手机号码')" prop="phonenumber">
      <el-input v-model="userForm.phonenumber" maxlength="11" />
    </el-form-item>
    <el-form-item :label="$tt('邮箱')" prop="email">
      <el-input v-model="userForm.email" maxlength="50" />
    </el-form-item>
    <el-form-item :label="$tt('性别')">
      <el-radio-group v-model="userForm.sex">
        <el-radio value="0">{{ $tt('男') }}</el-radio>
        <el-radio value="1">{{ $tt('女') }}</el-radio>
      </el-radio-group>
    </el-form-item>
    <el-form-item>
      <el-button type="primary" @click="submit">{{ $tt('保存') }}</el-button>
      <el-button type="danger" @click="close">{{ $tt('关闭') }}</el-button>
    </el-form-item>
  </el-form>
</template>

<script setup lang="ts">
import { tt } from '@/utils/i18n';
import { updateUserProfile } from '@/api/system/user';
import { propTypes } from '@/utils/propTypes';

const props = defineProps({
  user: propTypes.any.isRequired
});
const userForm = computed(() => props.user);
const { proxy } = getCurrentInstance() as ComponentInternalInstance;
const userRef = ref<ElFormInstance>();
const rule: ElFormRules = {
  nickName: [{ required: true, message: tt('用户昵称不能为空'), trigger: 'blur' }],
  email: [
    { required: true, message: tt('邮箱地址不能为空'), trigger: 'blur' },
    {
      type: 'email',
      message: tt('请输入正确的邮箱地址'),
      trigger: ['blur', 'change']
    }
  ],
  phonenumber: [
    {
      required: true,
      message: tt('手机号码不能为空'),
      trigger: 'blur'
    },
    { pattern: /^1[3456789][0-9]\d{8}$/, message: tt('请输入正确的手机号码'), trigger: 'blur' }
  ]
};
const rules = ref<ElFormRules>(rule);

/** 提交按钮 */
const submit = () => {
  userRef.value?.validate(async (valid: boolean) => {
    if (valid) {
      await updateUserProfile(props.user);
      proxy?.$modal.msgSuccess(tt('修改成功'));
    }
  });
};
/** 关闭按钮 */
const close = () => {
  proxy?.$tab.closePage();
};
</script>
