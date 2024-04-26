# pragma version 0.3.10
# pragma optimize gas
# pragma evm-version paris

"""
@title Uniswap V2 TWAP Bot
@license Apache 2.0
@author Volume.finance
"""

struct SwapInfo:
    path: DynArray[address, MAX_SIZE]
    amount: uint256

struct Deposit:
    depositor: address
    path: DynArray[address, MAX_SIZE]
    input_amount: uint256
    number_trades: uint256
    interval: uint256
    remaining_counts: uint256
    starting_time: uint256

interface UniswapV2Router:
    def WETH() -> address: pure
    def swapExactETHForTokensSupportingFeeOnTransferTokens(amountOutMin: uint256, path: DynArray[address, MAX_SIZE], to: address, deadline: uint256): payable
    def swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn: uint256, amountOutMin: uint256, path: DynArray[address, MAX_SIZE], to: address, deadline: uint256): nonpayable
    def swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn: uint256, amountOutMin: uint256, path: DynArray[address, MAX_SIZE], to: address, deadline: uint256): nonpayable

interface ERC20:
    def balanceOf(_owner: address) -> uint256: view
    def approve(_spender: address, _value: uint256) -> bool: nonpayable
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable

VETH: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE # Virtual ETH
WETH: immutable(address)
ROUTER: immutable(address)
MAX_SIZE: constant(uint256) = 8
DENOMINATOR: constant(uint256) = 10000
compass: public(address)
deposit_list: public(HashMap[uint256, Deposit])
next_deposit: public(uint256)
refund_wallet: public(address)
fee: public(uint256)
paloma: public(bytes32)
service_fee_collector: public(address)
service_fee: public(uint256)

event Deposited:
    deposit_id: uint256
    token0: address
    token1: address
    input_amount: uint256
    number_trades: uint256
    interval: uint256
    starting_time: uint256
    depositor: address

event Swapped:
    deposit_id: uint256
    remaining_counts: uint256
    amount: uint256
    out_amount: uint256

event Canceled:
    deposit_id: uint256

event UpdateCompass:
    old_compass: address
    new_compass: address

event UpdateRefundWallet:
    old_refund_wallet: address
    new_refund_wallet: address

event UpdateFee:
    old_fee: uint256
    new_fee: uint256

event SetPaloma:
    paloma: bytes32

event UpdateServiceFeeCollector:
    old_service_fee_collector: address
    new_service_fee_collector: address

event UpdateServiceFee:
    old_service_fee: uint256
    new_service_fee: uint256

@external
def __init__(_compass: address, router: address, _refund_wallet: address, _fee: uint256, _service_fee_collector: address, _service_fee: uint256):
    self.compass = _compass
    ROUTER = router
    WETH = UniswapV2Router(ROUTER).WETH()
    self.refund_wallet = _refund_wallet
    self.fee = _fee
    self.service_fee_collector = _service_fee_collector
    assert _service_fee < DENOMINATOR
    self.service_fee = _service_fee
    log UpdateCompass(empty(address), _compass)
    log UpdateRefundWallet(empty(address), _refund_wallet)
    log UpdateFee(0, _fee)
    log UpdateServiceFeeCollector(empty(address), _service_fee_collector)
    log UpdateServiceFee(0, _service_fee)

@external
@payable
@nonreentrant('lock')
def deposit(swap_infos: DynArray[SwapInfo, MAX_SIZE], number_trades: uint256, interval: uint256, starting_time: uint256):
    _value: uint256 = msg.value
    _fee: uint256 = self.fee
    if _fee > 0:
        _fee = _fee * number_trades
        assert _value >= _fee, "Insufficient fee"
        send(self.refund_wallet, _fee)
        _value = unsafe_sub(_value, _fee)
    _next_deposit: uint256 = self.next_deposit
    for swap_info in swap_infos:
        last_index: uint256 = unsafe_sub(len(swap_info.path), 1)
        amount: uint256 = 0
        if swap_info.path[0] == VETH:
            amount = swap_info.amount
            assert _value >= amount, "Insufficient deposit"
            _value = unsafe_sub(_value, amount)
        else:
            amount = ERC20(swap_info.path[0]).balanceOf(self)
            assert ERC20(swap_info.path[0]).transferFrom(msg.sender, self, swap_info.amount, default_return_value=True), "Failed transferFrom"
            amount = ERC20(swap_info.path[0]).balanceOf(self) - amount
        _starting_time: uint256 = starting_time
        if starting_time <= block.timestamp:
            _starting_time = block.timestamp
        assert number_trades > 0, "Wrong trade count"
        self.deposit_list[_next_deposit] = Deposit({
            depositor: msg.sender,
            path: swap_info.path,
            input_amount: swap_info.amount,
            number_trades: number_trades,
            interval: interval,
            remaining_counts: number_trades,
            starting_time: _starting_time
        })
        log Deposited(_next_deposit, swap_info.path[0], swap_info.path[last_index], amount, number_trades, interval, _starting_time, msg.sender)
        _next_deposit = unsafe_add(_next_deposit, 1)
    self.next_deposit = _next_deposit
    if _value > 0:
        send(msg.sender, _value)

@internal
def _safe_transfer(_token: address, _to: address, _value: uint256):
    assert ERC20(_token).transfer(_to, _value, default_return_value=True), "Failed transfer"

@internal
def _swap(deposit_id: uint256, remaining_count: uint256, amount_out_min: uint256) -> uint256:
    _deposit: Deposit = self.deposit_list[deposit_id]
    assert _deposit.remaining_counts > 0 and _deposit.remaining_counts == remaining_count, "wrong count"
    _amount: uint256 = _deposit.input_amount / _deposit.remaining_counts
    _deposit.input_amount -= _amount
    _deposit.remaining_counts -= 1
    self.deposit_list[deposit_id] = _deposit
    _out_amount: uint256 = 0
    _path: DynArray[address, MAX_SIZE] = _deposit.path
    last_index: uint256 = unsafe_sub(len(_deposit.path), 1)
    if _deposit.path[0] == VETH:
        _path[0] = WETH
        _out_amount = ERC20(_deposit.path[last_index]).balanceOf(self)
        UniswapV2Router(ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens(amount_out_min, _path, self, block.timestamp, value=_amount)
        _out_amount = ERC20(_deposit.path[last_index]).balanceOf(self) - _out_amount
    else:
        assert ERC20(_deposit.path[0]).approve(ROUTER, _amount, default_return_value=True), "Failed approve"
        if _deposit.path[last_index] == VETH:
            _path[last_index] = WETH
            _out_amount = self.balance
            UniswapV2Router(ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(_amount, amount_out_min, _path, self, block.timestamp)
            _out_amount = self.balance - _out_amount
        else:
            _out_amount = ERC20(_deposit.path[last_index]).balanceOf(self)
            UniswapV2Router(ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(_amount, amount_out_min, _path, self, block.timestamp)
            _out_amount = ERC20(_deposit.path[last_index]).balanceOf(self) - _out_amount
    _service_fee: uint256 = self.service_fee
    service_fee_amount: uint256 = 0
    if _service_fee > 0:
        service_fee_amount = unsafe_div(_out_amount * _service_fee, DENOMINATOR)
    if _deposit.path[last_index] == VETH:
        if service_fee_amount > 0:
            send(self.service_fee_collector, service_fee_amount)
            send(_deposit.depositor, unsafe_sub(_out_amount, service_fee_amount))
        else:
            send(_deposit.depositor, _out_amount)
    else:
        if service_fee_amount > 0:
            self._safe_transfer(_deposit.path[last_index], self.service_fee_collector, service_fee_amount)
            self._safe_transfer(_deposit.path[last_index], _deposit.depositor, unsafe_sub(_out_amount, service_fee_amount))
        else:
            self._safe_transfer(_deposit.path[last_index], _deposit.depositor, _out_amount)
    log Swapped(deposit_id, _deposit.remaining_counts, _amount, _out_amount)
    return _out_amount

@internal
def _paloma_check():
    assert msg.sender == self.compass, "Not compass"
    assert self.paloma == convert(slice(msg.data, unsafe_sub(len(msg.data), 32), 32), bytes32), "Invalid paloma"

@external
@nonreentrant('lock')
def multiple_swap(deposit_id: DynArray[uint256, MAX_SIZE], remaining_counts: DynArray[uint256, MAX_SIZE], amount_out_min: DynArray[uint256, MAX_SIZE]):
    self._paloma_check()
    _len: uint256 = len(deposit_id)
    assert _len == len(amount_out_min) and _len == len(remaining_counts), "Validation error"
    for i in range(MAX_SIZE):
        if i >= len(deposit_id):
            break
        self._swap(deposit_id[i], remaining_counts[i], amount_out_min[i])

@external
def multiple_swap_view(deposit_id: DynArray[uint256, MAX_SIZE], remaining_counts: DynArray[uint256, MAX_SIZE]) -> DynArray[uint256, MAX_SIZE]:
    assert msg.sender == empty(address) # only for view function
    _len: uint256 = len(deposit_id)
    res: DynArray[uint256, MAX_SIZE] = []
    for i in range(MAX_SIZE):
        if i >= len(deposit_id):
            break
        res.append(self._swap(deposit_id[i], remaining_counts[i], 1))
    return res

@external
@nonreentrant('lock')
def cancel(deposit_id: uint256):
    _deposit: Deposit = self.deposit_list[deposit_id]
    assert _deposit.depositor == msg.sender, "Unauthorized"
    assert _deposit.input_amount > 0, "all traded"
    if _deposit.path[0] == VETH:
        send(msg.sender, _deposit.input_amount)
    else:
        self._safe_transfer(_deposit.path[0], msg.sender, _deposit.input_amount)
    _deposit.input_amount = 0
    _deposit.remaining_counts = 0
    self.deposit_list[deposit_id] = _deposit
    log Canceled(deposit_id)

@external
def update_compass(new_compass: address):
    self._paloma_check()
    self.compass = new_compass
    log UpdateCompass(msg.sender, new_compass)

@external
def update_refund_wallet(new_refund_wallet: address):
    self._paloma_check()
    old_refund_wallet: address = self.refund_wallet
    self.refund_wallet = new_refund_wallet
    log UpdateRefundWallet(old_refund_wallet, new_refund_wallet)

@external
def update_fee(new_fee: uint256):
    self._paloma_check()
    old_fee: uint256 = self.fee
    self.fee = new_fee
    log UpdateFee(old_fee, new_fee)

@external
def set_paloma():
    assert msg.sender == self.compass and self.paloma == empty(bytes32) and len(msg.data) == 36, "Invalid"
    _paloma: bytes32 = convert(slice(msg.data, 4, 32), bytes32)
    self.paloma = _paloma
    log SetPaloma(_paloma)

@external
def update_service_fee_collector(new_service_fee_collector: address):
    self._paloma_check()
    old_service_fee_collector: address = self.service_fee_collector
    self.service_fee_collector = new_service_fee_collector
    log UpdateServiceFeeCollector(old_service_fee_collector, new_service_fee_collector)

@external
def update_service_fee(new_service_fee: uint256):
    self._paloma_check()
    assert new_service_fee < DENOMINATOR
    old_service_fee: uint256 = self.service_fee
    self.service_fee = new_service_fee
    log UpdateServiceFee(old_service_fee, new_service_fee)

@external
@payable
def __default__():
    assert msg.sender == ROUTER
