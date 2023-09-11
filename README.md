# Time Weighted Average Price (TWAP) trading bot using pancakeswap

## User function

### deposit

In order to use DCA trading bot, users should deposit their token first with trading information. Of course, users need to approve their token to the DCA bot smart contract.

| field         | type      | description                       |
| ------------- | --------- | --------------------------------- |
| path          | address[] | Token swap path in pancakeswap    |
| input_amount  | uint256   | Total token amount to trade       |
| number_trades | uint256   | Number of trades                  |
| interval      | uint256   | Interval between trades           |
| starting_time | uint256   | Timestamp of starting DCA trading |

## Bot functions

### swap

The bot script will run this swap function with swap ID and amount_out_min (for prevent high slippage) when the dca trading is needed. This function should be called from compass-evm from Paloma for safety. Otherwise, it can't run.

| field         | type    | description                                      |
| ------------- | ------- | ------------------------------------------------ |
| swap_id       | uint256 | Swap ID that is going to trade                   |
| amout_out_min | uint256 | minimum token amount to receive in current trade |

### triggerable_deposit

This view function is to get which swap ID is reached to trade time and the expected amount of the trade. This will be used to run swap function.

Returning data

| type    | description                                  |
| ------- | -------------------------------------------- |
| uint256 | swap id reached interval                     |
| uint256 | minimum token amount to receive in the trade |
| uint256 | remaining number of trade                    |

