import request from '@/utils/request';
import type { AxiosPromise } from 'axios';

/** 数据权限规则 */
export interface ScopeRuleVO {
  id?: number;
  roleId?: number;
  /** ALL / COMPANY / ORG_TREE / ORG / SELF */
  scopeType: string;
  scopeValue?: string | null;
  /** 法人或组织名称，后端翻译好回传 */
  scopeName?: string | null;
  canExport?: boolean;
  remark?: string;
}

export interface IdNameOption {
  id: number;
  name: string;
}

export interface ScopeOptionsVO {
  legalEntities: IdNameOption[];
  organizations: IdNameOption[];
  /** 组织架构尚未导入时为 true，前端据此给提示而不是给空下拉 */
  organizationEmpty: boolean;
}

export interface ScopeRuleSaveDTO {
  roleId: number;
  rules: ScopeRuleVO[];
}

export const listScopeRule = (roleId: number | string): AxiosPromise<ScopeRuleVO[]> => {
  return request({
    url: '/api/data-scope-rule/list',
    method: 'get',
    params: { roleId }
  });
};

export const getScopeOptions = (): AxiosPromise<ScopeOptionsVO> => {
  return request({
    url: '/api/data-scope-rule/options',
    method: 'get'
  });
};

export const saveScopeRule = (data: ScopeRuleSaveDTO): AxiosPromise<void> => {
  return request({
    url: '/api/data-scope-rule/save',
    method: 'post',
    data
  });
};
