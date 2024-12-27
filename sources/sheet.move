module liquidlogic_framework::sheet {

    // Dependencies

    use std::type_name::{get, TypeName};
    use sui::balance::{Balance};
    use sui::vec_map::{Self, VecMap};

    // Structs

    public struct Credit<phantom CoinType>(u64) has store;

    public struct Debt<phantom CoinType>(u64) has store;

    public struct Creditor(TypeName) has store, copy, drop;

    public struct Debtor(TypeName) has store, copy, drop;

    public struct Sheet<phantom Entity, phantom CoinType> has store {
        // Help record the credits and debts, not necessary
        credits: VecMap<Debtor, Credit<CoinType>>,
        debts: VecMap<Creditor, Debt<CoinType>>,
    }

    // Hot potato

    public struct Loan<phantom Creditor, phantom Debtor, phantom CoinType> {
        balance: Balance<CoinType>,
        credit: Option<Credit<CoinType>>,
        debt: Option<Debt<CoinType>>,
    }

    public struct Repayment<phantom Creditor, phantom Debtor, phantom CoinType> {
        balance: Balance<CoinType>,
        credit: Option<Credit<CoinType>>,
        debt: Option<Debt<CoinType>>,
    }

    public struct Collector<phantom Creditor, phantom Debtor, phantom CoinType> {
        requirement: u64,
        repayment: Option<Repayment<Creditor, Debtor, CoinType>>
    }

    // Errors

    const ENotEnoughRepayment: u64 = 0;
    fun err_not_enough_repayment() { abort ENotEnoughRepayment }

    const ERepayTooMuch: u64 = 1;
    fun err_repay_too_much() { abort ERepayTooMuch }

    const EDestroyNonEmptySheet: u64 = 2;
    fun err_destroy_not_empty_sheet() { abort EDestroyNonEmptySheet }

    const EAlreadyRepaid: u64 = 3;
    fun err_already_repaid() { abort EAlreadyRepaid }

    const ENoRepayment: u64 = 4;
    fun err_no_repayment() { abort ENoRepayment }

    const ECreditorNotFound: u64 = 5;
    fun err_creditor_not_found() { abort ECreditorNotFound }

    const EDebtorNotFound: u64 = 6;
    fun err_debtor_not_found() { abort EDebtorNotFound }

    // Public Funs

    public fun new<E: drop, T>(_: E): Sheet<E, T> {
        Sheet<E, T> {
            credits: vec_map::empty(),
            debts: vec_map::empty(),
        }
    }

    public fun loan<C: drop, D, T>(
        sheet: &mut Sheet<C, T>,
        balance: Balance<T>,
        _stamp: C,
    ): Loan<C, D, T> {
        let balance_value = balance.value();
        let mut loan = Loan {
            balance,
            credit: option::some(Credit(balance_value)),
            debt: option::some(Debt(balance_value)),
        };
        sheet.record_loan(&mut loan);
        loan
    }

    public fun receive<C, D: drop, T>(
        sheet: &mut Sheet<D, T>,
        mut loan: Loan<C, D, T>,
        _stamp: D,
    ): Balance<T> {
        sheet.record_receive(&mut loan);
        let Loan {
            balance,
            credit,
            debt,
        } = loan;
        credit.destroy_none();
        debt.destroy_none();
        balance
    }

    public fun dun<C: drop, D, T>(
        requirement: u64,
        _stamp: C,
    ): Collector<C, D, T> {
        Collector { requirement, repayment: option::none() }
    }

    public fun repay<C, D: drop, T>(
        sheet: &mut Sheet<D, T>,
        collector: &mut Collector<C, D, T>,
        balance: Balance<T>,
        _stamp: D,
    ) {
        if (collector.repayment.is_some()) {
            err_already_repaid();
        };
        let balance_value = balance.value();
        let repayment = Repayment {
            balance,
            credit: option::some(Credit(balance_value)),
            debt: option::some(Debt(balance_value)),
        };
        collector.repayment.fill(repayment);
        sheet.record_repay(collector);
    }

    public fun collect<C: drop, D, T>(
        sheet: &mut Sheet<C, T>,
        mut collector: Collector<C, D, T>,
        _stamp: C,
    ): Balance<T> {
        sheet.record_collect(&mut collector);
        let Collector { requirement, repayment } = collector;
        if (repayment.is_none()) {
            err_no_repayment();
        };
        let Repayment { 
            balance,
            credit,
            debt,
        } = repayment.destroy_some();
        credit.destroy_none();
        debt.destroy_none();
    
        if (requirement != balance.value()) {
            err_not_enough_repayment();
        };
        balance
    }

    public fun add_debtor<E: drop, T, D>(
        sheet: &mut Sheet<E, T>,
        _stamp: E,
    ) {
        sheet.credits.insert(debtor<D>(), Credit(0));
    }

    public fun add_creditor<E: drop, T, C>(
        sheet: &mut Sheet<E, T>,
        _stamp: E,
    ) {
        sheet.debts.insert(creditor<C>(), Debt(0));
    }

    public fun remove_debtor<E: drop, T, D>(
        sheet: &mut Sheet<E, T>,
        _stamp: E,
    ) {
        let debtor = debtor<D>();
        if (!sheet.credits.contains(&debtor)) {
            err_debtor_not_found();
        };
        let (_, credit) = sheet.credits.remove(&debtor);
        credit.destroy_credit();
    }

    public fun remove_creditor<E: drop, T, C>(
        sheet: &mut Sheet<E, T>,
        _stamp: E,
    ) {
        let creditor = creditor<C>();
        if (!sheet.debts.contains(&creditor)) {
            err_creditor_not_found();
        };
        let (_, debt) = sheet.debts.remove(&creditor);
        debt.destroy_debt();
    }

    // Internal Funs

    fun record_loan<C, D, T>(
        sheet: &mut Sheet<C, T>,
        loan: &mut Loan<C, D, T>,
    ): u64 {
        let credit = loan.credit.extract();
        let debtor = debtor<D>();
        if (!sheet.credits.contains(&debtor)) {
            err_debtor_not_found();
        };
        sheet.credits.get_mut(&debtor).add_credit(credit)
    }

    fun record_receive<C, D, T>(
        sheet: &mut Sheet<D, T>,
        loan: &mut Loan<C, D, T>,
    ): u64 {
        let debt = loan.debt.extract();
        let creditor = creditor<C>();
        if (!sheet.debts.contains(&creditor)) {
            err_creditor_not_found();
        };
        sheet.debts.get_mut(&creditor).add_debt(debt)
    }

    fun record_repay<C, D, T>(
        sheet: &mut Sheet<D, T>,
        collector: &mut Collector<C, D, T>,
    ): u64 {
        let repayment = collector.repayment.borrow_mut();
        let debt = repayment.debt.extract();
        let creditor = creditor<C>();
        if (!sheet.debts.contains(&creditor)) {
            err_creditor_not_found();
        };
        sheet.debts.get_mut(&creditor).sub_debt(debt)
    }

    fun record_collect<C, D, T>(
        sheet: &mut Sheet<C, T>,
        collector: &mut Collector<C, D, T>,
    ): u64 {
        let repayment = collector.repayment.borrow_mut();
        let credit = repayment.credit.extract();
        let debtor = debtor<D>();
        if (!sheet.credits.contains(&debtor)) {
            err_debtor_not_found();
        };
        sheet.credits.get_mut(&debtor).sub_credit(credit)
    }

    // Getter Funs

    public use fun loan_balance as Loan.balance;
    public fun loan_balance<C, D, T>(loan: &Loan<C, D, T>): &Balance<T> {
        &loan.balance
    }

    public use fun repayment_balance as Repayment.balance;
    public fun repayment_balance<C, D, T>(repayment: &Repayment<C, D, T>): &Balance<T> {
        &repayment.balance
    }

    public fun repayment<C, D, T>(
        collector: &Collector<C, D, T>,
    ): &Option<Repayment<C, D, T>> {
        &collector.repayment
    }

    public fun requirement<C, D, T>(collector: &Collector<C, D, T>): u64 {
        collector.requirement
    }

    public fun credits<E, T>(sheet: &Sheet<E, T>): &VecMap<Debtor, Credit<T>> {
        &sheet.credits
    }

    public fun debts<E, T>(sheet: &Sheet<E, T>): &VecMap<Creditor, Debt<T>> {
        &sheet.debts
    }

    public use fun credit_value as Credit.value;
    public fun credit_value<T>(credit: &Credit<T>): u64 {
        credit.0
    }

    public use fun debt_value as Debt.value;
    public fun debt_value<T>(debt: &Debt<T>): u64 {
        debt.0
    }

    public fun creditor<C>(): Creditor { Creditor(get<C>()) }

    public fun debtor<D>(): Debtor { Debtor(get<D>()) }

    // Internal Funs

    fun add_credit<T>(self: &mut Credit<T>, credit: Credit<T>): u64 {
        let Credit(value) = credit;
        let result = self.0 + value;
        self.0 = result;
        result
    }

    fun sub_credit<T>(self: &mut Credit<T>, credit: Credit<T>): u64 {
        let Credit(value) = credit;
        if (self.0 < value) {
            err_repay_too_much();
        };
        let result = self.0 - value;
        self.0 = result;
        result
    }

    fun add_debt<T>(self: &mut Debt<T>, debt: Debt<T>): u64 {
        let Debt(value) = debt;
        let result = self.0 + value;
        self.0 = result;
        result
    }

    fun sub_debt<T>(self: &mut Debt<T>, debt: Debt<T>): u64 {
        let Debt(value) = debt;
        if (self.0 < value) {
            err_repay_too_much();
        };
        let result = self.0 - value;
        self.0 = result;
        result
    }

    fun destroy_credit<T>(credit: Credit<T>) {
        let Credit(value) = credit;
        if (value > 0) {
            err_destroy_not_empty_sheet();
        };
    }

    fun destroy_debt<T>(credit: Debt<T>) {
        let Debt(value) = credit;
        if (value > 0) {
            err_destroy_not_empty_sheet();
        };
    }
}