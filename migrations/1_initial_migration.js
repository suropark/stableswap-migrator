const Migrations = artifacts.require('Migrations');
const Zap = artifacts.require('Zap');
module.exports = function (deployer) {
  deployer.deploy(Migrations);
  deployer.deploy(Zap, tokens, swap, lp);
};

const tokens = [
  '0xcee8faf64bb97a73bb51e115aa89c17ffa8dd167',
  '0x754288077d0ff82af7a5317c7cb8c444d421d103',
  '0x5c74070fdea071359b86082bd9f9b3deaafbe32b',
  '0x210bc03f49052169d5588a52c317f71cf2078b85',
];
const swap = '0x5653ab94b0b4bcf91986827eb45f4f9c95d13454';
const lp = '0xE07d787Bb31e66FfEc103951f94CCfE58206Be17';
