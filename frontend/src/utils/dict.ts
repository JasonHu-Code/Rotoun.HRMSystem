import { getDicts } from '@/api/system/dict/data';
import { useDictStore } from '@/store/modules/dict';
import { tt } from '@/utils/i18n';

/**
 * 字典标签来自数据库 sys_dict_data.dict_label，本身就是中文。
 * 各页面把 dict.label 直接渲染到下拉/单选/标签上，如果不在这个唯一出口翻译，
 * 切到英文后就会出现"英文界面里夹着中文选项"。只翻 label，value 保持原值不变。
 */
const toOption = (p: DictDataOption): DictDataOption => {
  const opt: DictDataOption = { label: tt(String(p.label)), value: p.value };
  if (p.elTagType) {
    opt.elTagType = p.elTagType;
  }
  if (p.elTagClass) {
    opt.elTagClass = p.elTagClass;
  }
  return opt;
};

/**
 * 获取字典数据
 */
export const useDict = (...args: string[]): { [key: string]: DictDataOption[] } => {
  const res = ref<{
    [key: string]: DictDataOption[];
  }>({});

  args.forEach(async (dictType) => {
    res.value[dictType] = [];
    const dicts = useDictStore().getDict(dictType);
    if (dicts) {
      res.value[dictType] = dicts;
    } else {
      await getDicts(dictType).then((resp) => {
        res.value[dictType] = resp.data.map(
          (p): DictDataOption => toOption({ label: p.dictLabel, value: p.dictValue, elTagType: p.listClass, elTagClass: p.cssClass })
        );
        useDictStore().setDict(dictType, res.value[dictType]);
      });
    }
  });
  return res.value;
};
