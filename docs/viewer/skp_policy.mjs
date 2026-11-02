// Compatibility gate over the upstream parser's model, never a SKP parser.
// Rendering covers mesh surfaces; SketchUp authoring annotations are not GLB.
export function assertSkpDisplayCompatibility(model, legacy) {
  const definitions = [model.root, ...model.definitions.values()].filter(Boolean);
  let sourceFaceCount = 0;
  for (const definition of definitions) {
    for (const face of definition.faces ?? []) {
      sourceFaceCount++;
      if (face.uvProjected || face.uvProjectedBack) {
        throw new Error('此 SKP 含投影纹理，当前导入器无法保真显示；请从 SketchUp 导出 GLB');
      }
    }
  }
  if (!sourceFaceCount) throw new Error('SKP 中没有可显示的模型面');
  for (const material of model.materials) {
    if (!material.texture) continue;
    // Current upstream only exposes projected flags on the legacy parser path.
    // Reject modern textured files rather than silently accepting approximated UVs.
    if (!legacy) throw new Error('此版本 SKP 的纹理映射尚未通过保真验证；请从 SketchUp 导出 GLB');
    if (!material.texture.data?.byteLength) throw new Error('SKP 纹理数据缺失；请从 SketchUp 导出包含纹理的 GLB');
  }
  return { sourceVersion: model.version, sourceFaceCount, legacy,
    scope: 'mesh-surfaces', converter: 'openskp', converterRevision: '13ae161fa0108647a04ad5730776120bb6fe8c83' };
}
