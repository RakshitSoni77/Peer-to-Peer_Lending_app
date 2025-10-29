// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract P2PLending {
    enum LoanState { Requested, Funded, Repaid, Defaulted }

    struct Loan {
        address borrower;
        address lender;
        uint256 principal;      // amount borrowed
        uint256 interest;       // interest to be paid on top of principal
        uint256 duration;       // e.g., in seconds or blocks
        uint256 startTimestamp;
        LoanState state;
    }

    uint256 public loanCount;
    mapping(uint256 => Loan) public loans;

    // Mapping of lender deposits (funds that lenders add to platform)
    mapping(address => uint256) public lenderBalances;

    // Events
    event LoanRequested(uint256 loanId, address indexed borrower, uint256 principal, uint256 interest, uint256 duration);
    event LoanFunded(uint256 loanId, address indexed lender);
    event LoanRepaid(uint256 loanId);
    event LoanDefaulted(uint256 loanId);

    // Modifier to restrict to borrower of a loan
    modifier onlyBorrower(uint256 _loanId) {
        require(msg.sender == loans[_loanId].borrower, "Not borrower");
        _;
    }

    // Modifier to restrict to lender of a loan
    modifier onlyLender(uint256 _loanId) {
        require(msg.sender == loans[_loanId].lender, "Not lender");
        _;
    }

    // Function: borrower requests loan
    function requestLoan(uint256 _principal, uint256 _interest, uint256 _duration) external {
        require(_principal > 0, "Principal must be > 0");
        require(_duration > 0, "Duration must be > 0");

        loanCount += 1;
        loans[loanCount] = Loan({
            borrower: msg.sender,
            lender: address(0),
            principal: _principal,
            interest: _interest,
            duration: _duration,
            startTimestamp: 0,
            state: LoanState.Requested
        });

        emit LoanRequested(loanCount, msg.sender, _principal, _interest, _duration);
    }

    // Function: lender funds a loan
    function fundLoan(uint256 _loanId) external payable {
        Loan storage ln = loans[_loanId];
        require(ln.state == LoanState.Requested, "Loan not available");
        require(msg.value == ln.principal, "Sent value must equal principal");

        ln.lender = msg.sender;
        ln.startTimestamp = block.timestamp;
        ln.state = LoanState.Funded;

        // transfer to borrower
        (bool success, ) = ln.borrower.call{ value: msg.value }("");
        require(success, "Transfer to borrower failed");

        emit LoanFunded(_loanId, msg.sender);
    }

    // Function: borrower repays (principal + interest)
    function repayLoan(uint256 _loanId) external payable onlyBorrower(_loanId) {
        Loan storage ln = loans[_loanId];
        require(ln.state == LoanState.Funded, "Loan not funded or already closed");

        uint256 amountDue = ln.principal + ln.interest;
        require(msg.value >= amountDue, "Repayment amount insufficient");

        ln.state = LoanState.Repaid;

        // transfer repayment to lender
        (bool success, ) = ln.lender.call{ value: msg.value }("");
        require(success, "Transfer to lender failed");

        emit LoanRepaid(_loanId);
    }

    // Function: check for default (can be called by anyone)
    function checkDefault(uint256 _loanId) external {
        Loan storage ln = loans[_loanId];
        require(ln.state == LoanState.Funded, "Loan not in funded state");

        // if current time greater than start + duration and not repaid → default
        if (block.timestamp > ln.startTimestamp + ln.duration) {
            ln.state = LoanState.Defaulted;
            emit LoanDefaulted(_loanId);
        }
    }

    // Optional: withdraw lender unused balances, etc.
}
