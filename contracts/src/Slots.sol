// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {VRFConsumerBaseV2Plus} from "chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Slots is VRFConsumerBaseV2Plus, ReentrancyGuard {

    error NOT_ENOUGH_VALUE_SENT();

    /**********************************************************/
    // Chainlink VRF Variables                                     
    /**********************************************************/
    event RequestSent(uint256 requestId, address sender);
    event RandomessFullfilled();

    struct RequestStatus {
        bool fulfilled;
        bool exists; 
        uint256[] randomWords;
        address sender;
    }

    mapping(uint256 => RequestStatus) public s_requests;
    bool private requestSent = false;

    uint256 public s_subscriptionId = 75558647393495334727523129114451877592583646763669698795386107447017644955169;

    uint256[] public requestIds;
    uint256 public lastRequestId;

    // Current base
    bytes32 public keyHash = 0xdc2f87677b01473c763cb0aee938ed3341512f6057324a584e5944e786144d70;
    uint32 public callbackGasLimit = 10000000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;
    address private vrfCoordinator = 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634;

    /**********************************************************/
    // Slots Variables                                     
    /**********************************************************/

    uint256 private totalPot;
    
    uint256 private constant PRICE_PER_SPIN = 1e15;
    uint256 private constant BIG_JACKPOT_WIN = 777;
    uint256 private constant SMALL_JACKPOT_WIN = 22;

    address private immutable OWNER;
    address private immutable LINK_SUBSCRIPTION;


    constructor(address _link) VRFConsumerBaseV2Plus(vrfCoordinator) {
        OWNER = msg.sender;
        LINK_SUBSCRIPTION = _link;
    }

    /**********************************************************/
    // Slots Functions                                    
    /**********************************************************/

    function spin() external payable {
        if(msg.value < PRICE_PER_SPIN){
            revert NOT_ENOUGH_VALUE_SENT();
        }

        totalPot += msg.value;

        requestRandomWords();
    }

    function spinCallback(uint256 _requestId) internal {
        uint256 randomNumber = s_requests[_requestId].randomWords[0];
        
        uint256 lastThreeDigits = randomNumber % 1000;
        if (lastThreeDigits == BIG_JACKPOT_WIN) {
            bigPayout(s_requests[_requestId].sender);
            return;
        }

        uint256 lastTwoDigits = randomNumber % 100;
        if (lastTwoDigits % SMALL_JACKPOT_WIN == 0 && lastTwoDigits <= 88) {
            smallPayout(s_requests[_requestId].sender);
            return;
        }
        
        loseSpin();
    }

    function bigPayout(address _payout) internal nonReentrant() {
        (bool success, ) = payable(_payout).call{value: totalPot}("");

        if(success){
            totalPot = 0;
        }
    }

    function smallPayout(address _payout) internal nonReentrant() {
        uint256 payout = (totalPot * 10)/100;

        (bool success, ) = payable(_payout).call{value: payout}("");

        if(success){
            totalPot -= payout;
        }
    }

    function loseSpin() internal nonReentrant() {
        uint256 valueToLink = (PRICE_PER_SPIN * 15)/100;
        uint256 valueToCreator = (PRICE_PER_SPIN * 10)/100;

        payable(LINK_SUBSCRIPTION).call{value: valueToLink}("");
        payable(OWNER).call{value: valueToCreator}("");
    }

    /**********************************************************/
    // Chainlink VRF Functions                                    
    /**********************************************************/


    function requestRandomWords() internal {
        uint256 requestId;
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: true
                    })
                )
            })
        );

        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false,
            sender: msg.sender
        });

        requestIds.push(requestId);
        lastRequestId = requestId;
        requestSent = true;
        emit RequestSent(requestId, msg.sender);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;

        spinCallback(_requestId);

        emit RandomessFullfilled();
    }





    fallback() external payable {
        totalPot += msg.value;
    }

    receive() external payable {
        totalPot += msg.value;
    }
}