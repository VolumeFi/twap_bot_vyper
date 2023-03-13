#!/usr/bin/python3

import pytest

@pytest.fixture(scope="session")
def DCAContract(accounts, project):
    return accounts[0].deploy(project.dca_pancakeswap, accounts[0])