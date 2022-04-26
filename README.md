1. sudo npm install -g truffle 명령어로 truffle을 설치합니다.

2. truffle init으로 프로젝트를 생성하고
   npm init
   npm install @openzeppelin/contracts 
   npm install caver-js-ext-kas
   패키지들을 설치합니다.

3. 기본적으로 contracts 폴더 안에 sol 파일을 작성합니다.

4. test는 js(mocha, chai)를 활용해서 진행합니다.(truffle test test/파일이름 으로 단일 테스트 진행)

5. truffle compile로 컴파일 진행합니다. => build 폴더가 생성되고 해당 폴더 안에 abi, bytecode가 만들어집니다.

6. migrations 폴더에서 배포 코드를 추가해야합니다. 
    => 2_deploy_smart_contract.js 라는 이름으로 파일을 생성하고 아래 코드를 넣어주세요

    
      const --- = artifacts.require("---");

      module.exports = function (deployer) {
      deployer.deploy(---);
      };
    

(7. ganche-cli -d -m ${amy word} => 니모닉 단어 넣어서 실행시키면 항상 같은 주소 제공)

8. truffle-config.js 파일에서 네트워크 설정합니다.(지갑도 정할 수 있음), Ted가 드리는 파일을 그대로 쓰세요.(kas를 사용해 배포예정)

9. truffle migrate --network kasCypress 으로 배포합니다.(migrations 폴더 안에 js 파일들이 실행된 것을 확인 가능)

10. 다시 배포할 때는 truffle migrate --reset을 사용합니다.

(11. truffle console 도 사용할 수 있음 => e.g ${} 입력하면 build 폴더의 ${}.json에 접근해서 조회 가능)
 

