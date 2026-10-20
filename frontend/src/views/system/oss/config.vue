<template>
  <div class="p-2">
    <transition :enter-active-class="proxy?.animate.searchAnimate.enter" :leave-active-class="proxy?.animate.searchAnimate.leave">
      <div v-show="showSearch" class="mb-[10px]">
        <el-card shadow="hover">
          <el-form ref="queryFormRef" :model="queryParams" :inline="true">
            <el-form-item :label="$tt('配置key')" prop="configKey">
              <el-input v-model="queryParams.configKey" :placeholder="$tt('配置key')" clearable @keyup.enter="handleQuery" />
            </el-form-item>
            <el-form-item :label="$tt('桶名称')" prop="bucketName">
              <el-input v-model="queryParams.bucketName" :placeholder="$tt('请输入桶名称')" clearable @keyup.enter="handleQuery" />
            </el-form-item>
            <el-form-item :label="$tt('是否默认')" prop="status">
              <el-select v-model="queryParams.status" :placeholder="$tt('请选择状态')" clearable>
                <el-option key="0" :label="$tt('是')" value="0" />
                <el-option key="1" :label="$tt('否')" value="1" />
              </el-select>
            </el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="handleQuery">{{ $tt('搜索') }}</el-button>
              <el-button icon="Refresh" @click="resetQuery">{{ $tt('重置') }}</el-button>
            </el-form-item>
          </el-form>
        </el-card>
      </div>
    </transition>

    <el-card shadow="hover">
      <template #header>
        <el-row :gutter="10" class="mb8">
          <el-col :span="1.5">
            <el-button v-hasPermi="['system:ossConfig:add']" type="primary" plain icon="Plus" @click="handleAdd">{{ $tt('新增') }}</el-button>
          </el-col>
          <el-col :span="1.5">
            <el-button v-hasPermi="['system:ossConfig:edit']" type="success" plain icon="Edit" :disabled="single" @click="handleUpdate()"
              >{{ $tt('修改') }}</el-button
            >
          </el-col>
          <el-col :span="1.5">
            <el-button v-hasPermi="['system:ossConfig:remove']" type="danger" plain icon="Delete" :disabled="multiple" @click="handleDelete()">{{ $tt('删除') }}</el-button>
          </el-col>
          <right-toolbar v-model:show-search="showSearch" @query-table="getList"></right-toolbar>
        </el-row>
      </template>

      <el-table v-loading="loading" border :data="ossConfigList" @selection-change="handleSelectionChange">
        <el-table-column type="selection" width="55" align="center" />
        <el-table-column v-if="columns[0].visible" :label="$tt('主建')" align="center" prop="ossConfigId" />
        <el-table-column v-if="columns[1].visible" :label="$tt('配置key')" align="center" prop="configKey" />
        <el-table-column v-if="columns[2].visible" :label="$tt('访问站点')" align="center" prop="endpoint" width="200" />
        <el-table-column v-if="columns[3].visible" :label="$tt('自定义域名')" align="center" prop="domain" width="200" />
        <el-table-column v-if="columns[4].visible" :label="$tt('桶名称')" align="center" prop="bucketName" />
        <el-table-column v-if="columns[5].visible" :label="$tt('前缀')" align="center" prop="prefix" />
        <el-table-column v-if="columns[6].visible" :label="$tt('域')" align="center" prop="region" />
        <el-table-column v-if="columns[7].visible" :label="$tt('桶权限类型')" align="center" prop="accessPolicy">
          <template #default="scope">
            <el-tag v-if="scope.row.accessPolicy === '0'" type="warning">private</el-tag>
            <el-tag v-if="scope.row.accessPolicy === '1'" type="success">public</el-tag>
            <el-tag v-if="scope.row.accessPolicy === '2'" type="info">custom</el-tag>
          </template>
        </el-table-column>
        <el-table-column v-if="columns[8].visible" :label="$tt('是否默认')" align="center" prop="status">
          <template #default="scope">
            <el-switch v-model="scope.row.status" active-value="0" inactive-value="1" @change="handleStatusChange(scope.row)"></el-switch>
          </template>
        </el-table-column>
        <el-table-column :label="$tt('操作')" fixed="right" align="center" width="150" class-name="small-padding">
          <template #default="scope">
            <el-tooltip :content="$tt('修改')" placement="top">
              <el-button v-hasPermi="['system:ossConfig:edit']" link type="primary" icon="Edit" @click="handleUpdate(scope.row)"></el-button>
            </el-tooltip>
            <el-tooltip :content="$tt('删除')" placement="top">
              <el-button v-hasPermi="['system:ossConfig:remove']" link type="primary" icon="Delete" @click="handleDelete(scope.row)"></el-button>
            </el-tooltip>
          </template>
        </el-table-column>
      </el-table>

      <pagination v-show="total > 0" v-model:page="queryParams.pageNum" v-model:limit="queryParams.pageSize" :total="total" @pagination="getList" />
    </el-card>
    <!-- 添加或修改对象存储配置对话框 -->
    <el-dialog v-model="dialog.visible" :title="dialog.title" width="800px" append-to-body>
      <el-form ref="ossConfigFormRef" :model="form" :rules="rules" label-width="120px">
        <el-form-item :label="$tt('配置key')" prop="configKey">
          <el-input v-model="form.configKey" :placeholder="$tt('请输入配置key')" />
        </el-form-item>
        <el-form-item :label="$tt('访问站点')" prop="endpoint">
          <el-input v-model="form.endpoint" :placeholder="$tt('请输入访问站点')">
            <template #prefix>
              <span style="color: #999">{{ protocol }}</span>
            </template>
          </el-input>
        </el-form-item>
        <el-form-item :label="$tt('自定义域名')" prop="domain">
          <el-input v-model="form.domain" :placeholder="$tt('请输入自定义域名')">
            <template #prefix>
              <span style="color: #999">{{ protocol }}</span>
            </template>
          </el-input>
        </el-form-item>
        <el-form-item label="accessKey" prop="accessKey">
          <el-input v-model="form.accessKey" :placeholder="$tt('请输入accessKey')" />
        </el-form-item>
        <el-form-item label="secretKey" prop="secretKey">
          <el-input v-model="form.secretKey" :placeholder="$tt('请输入秘钥')" show-password />
        </el-form-item>
        <el-form-item :label="$tt('桶名称')" prop="bucketName">
          <el-input v-model="form.bucketName" :placeholder="$tt('请输入桶名称')" />
        </el-form-item>
        <el-form-item :label="$tt('前缀')" prop="prefix">
          <el-input v-model="form.prefix" :placeholder="$tt('请输入前缀')" />
        </el-form-item>
        <el-form-item :label="$tt('是否HTTPS')">
          <el-radio-group v-model="form.isHttps">
            <el-radio v-for="dict in sys_yes_no" :key="dict.value" :value="dict.value">{{ dict.label }}</el-radio>
          </el-radio-group>
        </el-form-item>
        <el-form-item :label="$tt('桶权限类型')">
          <el-radio-group v-model="form.accessPolicy">
            <el-radio value="0">private</el-radio>
            <el-radio value="1">public</el-radio>
            <el-radio value="2">custom</el-radio>
          </el-radio-group>
        </el-form-item>
        <el-form-item :label="$tt('域')" prop="region">
          <el-input v-model="form.region" :placeholder="$tt('请输入域')" />
        </el-form-item>
        <el-form-item :label="$tt('备注')" prop="remark">
          <el-input v-model="form.remark" type="textarea" :placeholder="$tt('请输入内容')" />
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="dialog-footer">
          <el-button :loading="buttonLoading" type="primary" @click="submitForm">{{ $tt('确 定') }}</el-button>
          <el-button @click="cancel">{{ $tt('取 消') }}</el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup name="OssConfig" lang="ts">
import { tt } from '@/utils/i18n';
import { listOssConfig, getOssConfig, delOssConfig, addOssConfig, updateOssConfig, changeOssConfigStatus } from '@/api/system/ossConfig';
import { OssConfigForm, OssConfigQuery, OssConfigVO } from '@/api/system/ossConfig/types';

const { proxy } = getCurrentInstance() as ComponentInternalInstance;
const { sys_yes_no } = toRefs<any>(proxy?.useDict('sys_yes_no'));

const ossConfigList = ref<OssConfigVO[]>([]);
const buttonLoading = ref(false);
const loading = ref(true);
const showSearch = ref(true);
const ids = ref<Array<number | string>>([]);
const single = ref(true);
const multiple = ref(true);
const total = ref(0);

const queryFormRef = ref<ElFormInstance>();
const ossConfigFormRef = ref<ElFormInstance>();

const dialog = reactive<DialogOption>({
  visible: false,
  title: ''
});

// 列显隐信息
const columns = ref<FieldOption[]>([
  { key: 0, label: tt('主建'), visible: false },
  { key: 1, label: tt('配置key'), visible: true },
  { key: 2, label: tt('访问站点'), visible: true },
  { key: 3, label: tt('自定义域名'), visible: true },
  { key: 4, label: tt('桶名称'), visible: true },
  { key: 5, label: tt('前缀'), visible: true },
  { key: 6, label: tt('域'), visible: true },
  { key: 7, label: tt('桶权限类型'), visible: true },
  { key: 8, label: tt('状态'), visible: true }
]);

const initFormData: OssConfigForm = {
  ossConfigId: undefined,
  configKey: '',
  accessKey: '',
  secretKey: '',
  bucketName: '',
  prefix: '',
  endpoint: '',
  domain: '',
  isHttps: 'N',
  accessPolicy: '1',
  region: '',
  status: '1',
  remark: ''
};
const data = reactive<PageData<OssConfigForm, OssConfigQuery>>({
  form: { ...initFormData },
  // 查询参数
  queryParams: {
    pageNum: 1,
    pageSize: 10,
    configKey: '',
    bucketName: '',
    status: ''
  },
  rules: {
    configKey: [{ required: true, message: tt('configKey不能为空'), trigger: 'blur' }],
    accessKey: [
      { required: true, message: tt('accessKey不能为空'), trigger: 'blur' },
      {
        min: 2,
        max: 200,
        message: tt('accessKey长度必须介于 2 和 100 之间'),
        trigger: 'blur'
      }
    ],
    secretKey: [
      { required: true, message: tt('secretKey不能为空'), trigger: 'blur' },
      {
        min: 2,
        max: 100,
        message: tt('secretKey长度必须介于 2 和 100 之间'),
        trigger: 'blur'
      }
    ],
    bucketName: [
      { required: true, message: tt('bucketName不能为空'), trigger: 'blur' },
      {
        min: 2,
        max: 100,
        message: tt('bucketName长度必须介于 2 和 100 之间'),
        trigger: 'blur'
      }
    ],
    endpoint: [
      { required: true, message: tt('endpoint不能为空'), trigger: 'blur' },
      {
        min: 2,
        max: 100,
        message: tt('endpoint名称长度必须介于 2 和 100 之间'),
        trigger: 'blur'
      }
    ],
    accessPolicy: [{ required: true, message: tt('accessPolicy不能为空'), trigger: 'blur' }]
  }
});

const { queryParams, form, rules } = toRefs(data);

const protocol = computed(() => (form.value.isHttps === 'Y' ? 'https://' : 'http://'));

/** 查询对象存储配置列表 */
const getList = async () => {
  loading.value = true;
  const res = await listOssConfig(queryParams.value);
  ossConfigList.value = res.rows;
  total.value = res.total;
  loading.value = false;
};
/** 取消按钮 */
const cancel = () => {
  dialog.visible = false;
  reset();
};
/** 表单重置 */
const reset = () => {
  form.value = { ...initFormData };
  ossConfigFormRef.value?.resetFields();
};
/** 搜索按钮操作 */
const handleQuery = () => {
  queryParams.value.pageNum = 1;
  getList();
};
/** 重置按钮操作 */
const resetQuery = () => {
  queryFormRef.value?.resetFields();
  handleQuery();
};
/** 选择条数  */
const handleSelectionChange = (selection: OssConfigVO[]) => {
  ids.value = selection.map((item) => item.ossConfigId);
  single.value = selection.length != 1;
  multiple.value = !selection.length;
};
/** 新增按钮操作 */
const handleAdd = () => {
  reset();
  dialog.visible = true;
  dialog.title = tt('添加对象存储配置');
};
/** 修改按钮操作 */
const handleUpdate = async (row?: OssConfigVO) => {
  reset();
  const ossConfigId = row?.ossConfigId || ids.value[0];
  const res = await getOssConfig(ossConfigId);
  Object.assign(form.value, res.data);
  dialog.visible = true;
  dialog.title = tt('修改对象存储配置');
};
/** 提交按钮 */
const submitForm = () => {
  ossConfigFormRef.value?.validate(async (valid: boolean) => {
    if (valid) {
      buttonLoading.value = true;
      if (form.value.ossConfigId) {
        await updateOssConfig(form.value).finally(() => (buttonLoading.value = false));
      } else {
        await addOssConfig(form.value).finally(() => (buttonLoading.value = false));
      }
      proxy?.$modal.msgSuccess(tt('新增成功'));
      dialog.visible = false;
      await getList();
    }
  });
};
/** 状态修改  */
const handleStatusChange = async (row: OssConfigVO) => {
  const text = row.status === '0' ? tt('启用') : tt('停用');
  try {
    await proxy?.$modal.confirm(tt('确认要"') + text + '""' + row.configKey + tt('"配置吗?'));
    await changeOssConfigStatus(row.ossConfigId, row.status, row.configKey);
    await getList();
    proxy?.$modal.msgSuccess(text + tt('成功'));
  } catch {
    return;
  } finally {
    row.status = row.status === '0' ? '1' : '0';
  }
};
/** 删除按钮操作 */
const handleDelete = async (row?: OssConfigVO) => {
  const ossConfigIds = row?.ossConfigId || ids.value;
  await proxy?.$modal.confirm(tt('是否确认删除OSS配置编号为"') + ossConfigIds + tt('"的数据项?'));
  loading.value = true;
  await delOssConfig(ossConfigIds).finally(() => (loading.value = false));
  await getList();
  proxy?.$modal.msgSuccess(tt('删除成功'));
};

onMounted(() => {
  getList();
});
</script>
