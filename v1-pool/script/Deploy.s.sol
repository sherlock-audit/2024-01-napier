// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {VyperDeployer} from "../lib/VyperDeployer.sol";
import {HardhatDeployer} from "hardhat-deployer/HardhatDeployer.sol";

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IWETH9} from "src/interfaces/external/IWETH9.sol";
import {CurveTricryptoFactory} from "src/interfaces/external/CurveTricryptoFactory.sol";
import {CurveTricryptoOptimizedWETH} from "src/interfaces/external/CurveTricryptoOptimizedWETH.sol";
import {ITranche} from "@napier/napier-v1/src/interfaces/ITranche.sol";
import {IPoolFactory} from "src/interfaces/IPoolFactory.sol";
import {PoolFactory} from "src/PoolFactory.sol";
import {NapierPool} from "src/NapierPool.sol";
import {NapierRouter} from "src/NapierRouter.sol";
import {Quoter} from "src/lens/Quoter.sol";

interface MockWETH is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface CurveV2TricryptoFactoryDeploy {
    function deploy_pool(
        string calldata _name,
        string calldata _symbol,
        address[3] calldata _coins,
        address _weth,
        uint256 implementation_id,
        uint256 A,
        uint256 gamma,
        uint256 mid_fee,
        uint256 out_fee,
        uint256 fee_gamma,
        uint256 allowed_extra_profit,
        uint256 adjustment_step,
        uint256 ma_exp_time,
        uint256[2] calldata initial_prices
    ) external returns (address);
}

contract CurveTricryptoPoolDeploy is Script {
    ///@notice create a new instance of VyperDeployer
    VyperDeployer vyperDeployer = new VyperDeployer();

    struct CurveV2Params {
        uint256 A;
        uint256 gamma;
        uint256 mid_fee;
        uint256 out_fee;
        uint256 fee_gamma;
        uint256 allowed_extra_profit;
        uint256 adjustment_step;
        uint256 ma_time;
        uint256[2] initial_prices;
    }

    function deployCurveV2Factory() public virtual returns (CurveTricryptoFactory) {
        address admin = msg.sender;
        address math = vyperDeployer.deployContract("lib/tricrypto-ng/contracts/main/CurveCryptoMathOptimized3");
        address views = vyperDeployer.deployContract("lib/tricrypto-ng/contracts/main/CurveCryptoViews3Optimized");
        address amm_blueprint =
            vyperDeployer.deployBlueprint("lib/tricrypto-ng/contracts/main/CurveTricryptoOptimizedWETH");
        CurveTricryptoFactory curveFactory = CurveTricryptoFactory(
            vyperDeployer.deployContract(
                "lib/tricrypto-ng/contracts/main/CurveTricryptoFactory", abi.encode(admin, admin)
            )
        );
        // setup tricrypto pool impl
        curveFactory.set_pool_implementation(amm_blueprint, 0);
        curveFactory.set_views_implementation(views);
        curveFactory.set_math_implementation(math);
        return curveFactory;
    }

    function deployCurveV2Pool(address factory, address weth, address[3] memory pts, CurveV2Params memory params)
        public
        returns (CurveTricryptoOptimizedWETH)
    {
        // deploy tricrypto pool with 3 Principal Tokens
        return CurveTricryptoOptimizedWETH(
            CurveV2TricryptoFactoryDeploy(address(factory)).deploy_pool(
                "Curve.fi WETH-PT1-PT2-PT3",
                "PT1PT2PT3",
                pts,
                weth,
                0, // <-------- 0th implementation index
                params.A,
                params.gamma,
                params.mid_fee,
                params.out_fee,
                params.fee_gamma,
                params.allowed_extra_profit,
                params.adjustment_step,
                params.ma_time,
                params.initial_prices
            )
        );
    }
}

contract PoolFactoryDeploy is Script {
    function deployNapierPoolFactory(address curveFactory, address owner) public virtual returns (PoolFactory) {
        return new PoolFactory(curveFactory, owner);
    }
}

contract TestDeploy is CurveTricryptoPoolDeploy, PoolFactoryDeploy {
    function deployCurveV2Factory() public override returns (CurveTricryptoFactory) {
        address math = vm.envAddress("MATH");
        address views = vm.envAddress("VIEWS");
        address amm_blueprint = vm.envAddress("AMM_BLUEPRINT");
        CurveTricryptoFactory curveFactory = CurveTricryptoFactory(vm.envAddress("CURVE_FACTORY"));
        // setup tricrypto pool impl
        curveFactory.set_pool_implementation(amm_blueprint, 0);
        curveFactory.set_views_implementation(views);
        curveFactory.set_math_implementation(math);

        return curveFactory;
    }

    function deployQuoter(PoolFactory poolFactory) public virtual returns (Quoter) {
        return new Quoter(poolFactory);
    }

    function deployNapierRouter(PoolFactory poolFactory, address weth) public virtual returns (NapierRouter) {
        return new NapierRouter(poolFactory, IWETH9(weth));
    }

    function run() public {
        vyperDeployer.setEvmVersion("shanghai");

        address weth = vm.envAddress("WETH");
        address underlying = vm.envAddress("UNDERLYING");
        address[3] memory pts = [vm.envAddress("PT1"), vm.envAddress("PT2"), vm.envAddress("PT3")];

        IPoolFactory.PoolConfig memory poolConfig = IPoolFactory.PoolConfig({
            initialAnchor: 1.2 * 1e18,
            scalarRoot: 8 * 1e18,
            lnFeeRateRoot: 0.000995 * 1e18,
            protocolFeePercent: 80,
            feeRecipient: msg.sender
        });

        // Curve v2 Pool Configuration
        CurveV2Params memory params = CurveV2Params({
            A: 270_000_000,
            gamma: 0.019 * 1e18,
            mid_fee: 1_000_000, // 0.01%
            out_fee: 20_000_000, // 0.20%
            fee_gamma: 0.22 * 1e18, // 0.22
            allowed_extra_profit: 0.000002 * 1e18,
            adjustment_step: 0.00049 * 1e18,
            ma_time: 3600,
            initial_prices: [uint256(1e18), 1e18]
        });

        vm.startBroadcast();
        CurveTricryptoFactory curveFactory = deployCurveV2Factory();
        CurveTricryptoOptimizedWETH basePool = deployCurveV2Pool(address(curveFactory), weth, pts, params);

        address owner = msg.sender;
        // deploy Napier Pool Factory
        PoolFactory poolFactory = deployNapierPoolFactory(address(curveFactory), owner);
        // deploy Napier Pool
        address pool = poolFactory.deploy(address(basePool), underlying, poolConfig);
        // deploy Napier Router
        NapierRouter router = deployNapierRouter(poolFactory, weth);
        poolFactory.authorizeCallbackReceiver(address(router));
        // deploy Quoter
        Quoter quoter = deployQuoter(poolFactory);
        poolFactory.authorizeCallbackReceiver(address(quoter));
        vm.stopBroadcast();

        console2.log("COPY AND PASTE THE FOLLOWING LINES TO .env FILE");
        console2.log("CURVE_FACTORY=%s", address(curveFactory));
        console2.log("BASE_POOL=%s", address(basePool));
        console2.log("POOL_FACTORY=%s", address(poolFactory));
        console2.log("POOL=%s", address(pool));
        console2.log("SWAP_ROUTER=%s", address(router));
        console2.log("QUOTER=%s", address(quoter));
        console2.log("LIB_CREATE2_POOL='Check broadcast log'");

        vm.startBroadcast();
        uint256 ONE_UNDERLYING = 10 ** ERC20(underlying).decimals();
        MockWETH(weth).mint(msg.sender, 10000000 * ONE_UNDERLYING);

        /// ISSUE PTS
        for (uint256 i = 0; i < pts.length; i++) {
            IERC20(underlying).approve(address(pts[i]), type(uint256).max);
            ITranche(pts[i]).issue(msg.sender, 100000 * ONE_UNDERLYING);
        }

        /// ADD LIQUIDITY TO TRICRYPTO
        for (uint256 i = 0; i < pts.length; i++) {
            IERC20(pts[i]).approve(address(router), type(uint256).max);
        }
        uint256 underlyingIn = 3000 * ONE_UNDERLYING;
        IERC20(underlying).approve(address(router), underlyingIn);

        /// ADD LIQUIDITY TO NAPIER POOL THROUGH ROUTER
        router.addLiquidity(
            pool,
            3000 * ONE_UNDERLYING,
            [1000 * ONE_UNDERLYING, 1000 * ONE_UNDERLYING, 1000 * ONE_UNDERLYING],
            0,
            msg.sender,
            block.timestamp + 10000
        );

        vm.stopBroadcast();
    }
}

/// @notice Script to deploy contracts compiled with Hardhat
// 1. Compile with custom compiler settings in Hardhat. Ensure that size of contracts doesn't exceed the limit of 24KB.
// `npx hardhat compile`
// 2. Deploy the contracts with the following command
// `AMM_BLUEPRINT=$AMM_BLUEPRINT CURVE_FACTORY=$CURVE_FACTORY VIEWS=$VIEWS MATH=$MATH WETH=$WETH UNDERLYING=$UNDERLYING PT1=$PT1 PT2=$PT2 PT3=$PT3 forge script --rpc-url=$RPC_URL --private-key=$PK -vvvv script/Deploy.s.sol:TestHardhatDeploy`
contract TestHardhatDeploy is TestDeploy {
    function deployNapierPoolFactory(address curveFactory, address owner) public override returns (PoolFactory) {
        return PoolFactory(
            HardhatDeployer.deployContract(
                "artifacts/src/PoolFactory.sol/PoolFactory.json",
                abi.encode(curveFactory, owner),
                HardhatDeployer.Library({
                    name: "Create2PoolLib",
                    path: "src/libs/Create2PoolLib.sol",
                    libAddress: HardhatDeployer.deployContract("artifacts/src/libs/Create2PoolLib.sol/Create2PoolLib.json")
                })
            )
        );
    }

    function deployQuoter(PoolFactory poolFactory) public override returns (Quoter) {
        return Quoter(
            HardhatDeployer.deployContract(
                "artifacts/src/lens/Quoter.sol/Quoter.json", abi.encode(address(poolFactory))
            )
        );
    }

    function deployNapierRouter(PoolFactory poolFactory, address weth) public override returns (NapierRouter) {
        return NapierRouter(
            payable(
                HardhatDeployer.deployContract(
                    "artifacts/src/NapierRouter.sol/NapierRouter.json", abi.encode(poolFactory, weth)
                )
            )
        );
    }
}
