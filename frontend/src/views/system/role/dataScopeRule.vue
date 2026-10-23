<template>
  <el-drawer v-model="visible" :title="tt('数据权限')" size="720px" append-to-body destroy-on-close>
    <div class="scope-role">
      <span>{{ tt('角色名称') }}</span>
      <b>{{ role?.roleName }}</b>
      <el-tag v-if="role?.roleKey" size="small" type="info" effect="plain">{{ role?.roleKey }}</el-tag>
    </div>

    <el-alert type="info" :closable="false" show-icon class="scope-tip">
      <template #title>
        {{ tt('规则取并集：多条规则时，能看到任一条范围内的数据；没有任何规则则该角色看不到业务数据。') }}
      </template>
    </el-alert>

    <el-table :data="rows" border size="small" class="scope-table">
      <el-table-column :label="tt('权限范围')" width="150">
        <template #default="{ row }">
          <el-select v-model="row.scopeType" size="small" @change="onTypeChange(row)">
            <el-option v-for="opt in scopeTypes" :key="opt.value" :label="tt(opt.label)" :value="opt.value" />
          </el-select>
        </template>
      </el-table-column>

      <el-table-column :label="tt('范围对象')" min-width="190">
        <template #default="{ row }">
          <el-select
            v-if="row.scopeType === 'COMPANY'"
            v-model="row.scopeValue"
            size="small"
            filterable
            clearable
            :placeholder="tt('选择法人')"
            style="width: 100%"
          >
            <el-option v-for="item in options.legalEntities" :key="item.id" :label="item.name" :value="String(item.id)" />
          </el-select>

          <el-select
            v-else-if="row.scopeType === 'ORG' || row.scopeType === 'ORG_TREE'"
            v-model="row.scopeValue"
            size="small"
            filterable
            clearable
            :placeholder="options.organizationEmpty ? tt('组织架构尚未导入') : tt('选择组织')"
            :disabled="options.organizationEmpty"
            style="width: 100%"
          >
            <el-option v-for="item in options.organizations" :key="item.id" :label="item.name" :value="String(item.id)" />
          </el-select>

          <span v-else class="scope-none">{{ tt('无需选择') }}</span>
        </template>
      </el-table-column>

      <el-table-column :label="tt('可导出')" width="80" align="center">
        <template #default="{ row }">
          <el-switch v-model="row.canExport" />
        </template>
      </el-table-column>

      <el-table-column :label="tt('备注')" min-width="130">
        <template #default="{ row }">
          <el-input v-model="row.remark" size="small" maxlength="200" :placeholder="tt('选填')" />
        </template>
      </el-table-column>

      <el-table-column :label="tt('操作')" width="60" align="center">
        <template #default="{ $index }">
          <el-button link type="danger" icon="Delete" @click="removeRow($index)" />
        </template>
      </el-table-column>
    </el-table>

    <el-button class="scope-add" icon="Plus" @click="addRow">{{ tt('添加一条范围') }}</el-button>
    <p class="scope-hint">{{ tt('「全量」已包含所有数据，不能与其他范围同时配置；配了全量的角色不需要再加其它规则。') }}</p>

    <template #footer>
      <el-button @click="visible = false">{{ tt('取消') }}</el-button>
      <el-button type="primary" :loading="saving" @click="submit">{{ tt('保存') }}</el-button>
    </template>
  </el-drawer>
</template>

<script setup lang="ts">
import { listScopeRule, getScopeOptions, saveScopeRule, type ScopeRuleVO, type ScopeOptionsVO } from '@/api/hr/dataScopeRule';
import { tt } from '@/utils/i18n';
import type { RoleVO } from '@/api/system/role/types';

const props = defineProps<{ modelValue: boolean; role: RoleVO | null }>();
const emit = defineEmits<{ 'update:modelValue': [boolean]; saved: [] }>();

const { proxy } = getCurrentInstance() as ComponentInternalInstance;

const visible = computed({
  get: () => props.modelValue,
  set: (v: boolean) => emit('update:modelValue', v)
});

const scopeTypes = [
  { value: 'ALL', label: '全量' },
  { value: 'COMPANY', label: '本公司' },
  { value: 'ORG_TREE', label: '组织及子树' },
  { value: 'ORG', label: '本组织' },
  { value: 'SELF', label: '仅本人' }
];

const rows = ref<ScopeRuleVO[]>([]);
const saving = ref(false);
const options = ref<ScopeOptionsVO>({ legalEntities: [], organizations: [], organizationEmpty: true });

/** 打开时拉数据：规则 + 下拉选项并行取，少一次串行等待 */
const load = async () => {
  if (!props.role?.roleId) return;
  const [ruleRes, optRes] = await Promise.all([listScopeRule(props.role.roleId), getScopeOptions()]);
  rows.value = (ruleRes.data || []).map((r: ScopeRuleVO) => ({ ...r, canExport: !!r.canExport }));
  options.value = optRes.data;
};

watch(
  () => props.modelValue,
  (open) => {
    if (open) {
      load();
    } else {
      rows.value = [];
    }
  }
);

const needsValue = (type: string) => type === 'COMPANY' || type === 'ORG' || type === 'ORG_TREE';

/** 切换范围类型时清掉上一个类型的取值，避免"本公司"里残留一个组织 ID */
const onTypeChange = (row: ScopeRuleVO) => {
  row.scopeValue = needsValue(row.scopeType) ? '' : null;
};

const addRow = () => {
  rows.value.push({ scopeType: 'SELF', scopeValue: null, canExport: false, remark: '' });
};

const removeRow = (index: number) => {
  rows.value.splice(index, 1);
};

const submit = async () => {
  if (!props.role?.roleId) return;

  // 前端先拦一层，和后端保持同一套口径；真正兜底仍以服务端校验为准
  const allCount = rows.value.filter((r) => r.scopeType === 'ALL').length;
  if (allCount > 0 && rows.value.length > 1) {
    proxy?.$modal.msgWarning(tt('「全量」已包含所有数据，不能与其他范围同时配置'));
    return;
  }
  const missing = rows.value.find((r) => needsValue(r.scopeType) && !r.scopeValue);
  if (missing) {
    proxy?.$modal.msgWarning(tt('请为每一行选择范围对象'));
    return;
  }

  saving.value = true;
  try {
    await saveScopeRule({ roleId: props.role.roleId, rules: rows.value });
    proxy?.$modal.msgSuccess(tt('保存成功'));
    visible.value = false;
    emit('saved');
  } finally {
    saving.value = false;
  }
};
</script>

<style lang="scss" scoped>
.scope-role {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
  color: var(--el-text-color-secondary);

  b {
    color: var(--el-text-color-primary);
  }
}

.scope-tip {
  margin-bottom: 12px;
}

.scope-table {
  margin-bottom: 12px;
}

.scope-none {
  color: var(--el-text-color-placeholder);
  font-size: 12px;
}

.scope-add {
  width: 100%;
  border-style: dashed;
}

.scope-hint {
  margin-top: 10px;
  font-size: 12px;
  line-height: 1.6;
  color: var(--el-text-color-secondary);
}
</style>
