// Existing CC0 museum captures; not yet published cloud posts.
export const examples = [
 {id:'cma-vase-1963-514',title:'彩瓷花瓶',description:'清代乾隆时期瓷器，彩色珐琅装饰与器物曲面。'},
 {id:'cma-dragon-jar-1986-85',title:'青花龙纹罐',description:'十八世纪朝鲜王朝瓷器，蓝色龙纹环绕白色釉面。'},
 {id:'cma-nataraja-1930-331',title:'青铜舞王像',description:'十一世纪南印度青铜雕塑，火焰环与多臂造型细节。'}
].map(work=>({...work,example:true,format:'glb',author:'开放授权示例',thumbnail:`assets/models/${work.id}.jpg`,model:`assets/models/${work.id}.glb`}));
