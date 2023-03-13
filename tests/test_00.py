#!/usr/bin/python3

from conftest import *
import ape
import math

def test_deposit(LOBContract, accounts, project):
    pancakeswap = project.UniswapV2Router.at("0x10ED43C718714eb63d5aA57B78B54704E256024E")
    usdt = project.USDT.at("0x55d398326f99059fF775485246999027B3197955")
    busd = project.BUSD.at("0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56")
