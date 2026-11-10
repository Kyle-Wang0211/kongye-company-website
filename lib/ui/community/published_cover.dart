// Canonical covers bound to exact, already published model content identities.
// A publisher-selected storage cover always takes precedence in WorkCard.
const _publishedModelCovers = <String, String>{
  '76db4d238fba298028a8be1157601e1c39159b1ebd4d73917ec3e66a549088b2/source.glb':
      'https://kongye.space/assets/models/cma-vase-1963-514-1346d3e18404.png',
  'f80acfbf8e1c88a096187a59c41dcb98e9a78c263044d5d8bc7a0187ab0e4ccc/source.glb':
      'https://kongye.space/assets/models/cma-dragon-jar-1986-85-9abcec526827.png',
  '3e4fce6fe2014ec83de31dd47930f7946b458ae615bf4b9526a2d65a0a944d2a/source.glb':
      'https://kongye.space/assets/models/cma-nataraja-1930-331-7a12fe4c5d6b.png',
};
String? publishedModelCover(String? modelStoragePath) =>
    _publishedModelCovers[modelStoragePath];
