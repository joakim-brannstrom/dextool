/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2015-2020
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "stub_ifs1.hpp"
#include <assert.h>
#include <iostream>

#define start_test()                                                                               \
    do {                                                                                           \
        std::cout << " # " << __func__ << "\t\t" << __FILE__ << ":" << __LINE__ << std::endl;      \
    } while (0)
#define msg(x)                                                                                     \
    do {                                                                                           \
        std::cout << __FILE__ << ":" << __LINE__ << " " << x << std::endl;                         \
    } while (0)

void test_stack_instance() {
    start_test();
    StubStubIfs1Manager m;
    StubIfs1 stub;
}

void test_heap_instance() {
    start_test();
    StubStubIfs1Manager m;
    Ifs1* obj = new StubIfs1;
    delete obj;
}

void test_pool() {
    start_test();
    StubIfs1* stub0;
    StubStubIfs1Manager m;

    msg("No instances created so a null pointer");
    assert(m.GetInstance() == 0);

    stub0 = new StubIfs1;
    msg("A instances created so expecting something other than null");
    assert(m.GetInstance() != 0);
}

void test_pool_delete() {
    start_test();
    StubStubIfs1Manager m;

    StubIfs1* stub = new StubIfs1;
    assert(m.GetInstance(0) == stub);
    delete stub;
    assert(m.GetInstance(0) == 0);
}

void test_pool_growth() {
    start_test();
    StubStubIfs1Manager m;

    msg("Forcing a resize of object pool");
    StubIfs1* stub0 = new StubIfs1;
    StubIfs1* stub1 = new StubIfs1;
    StubIfs1* stub2 = new StubIfs1;
    StubIfs1* stub3 = new StubIfs1;
    StubIfs1* stub4 = new StubIfs1;

    assert(m.GetInstance(0) == stub0);
    assert(m.GetInstance(1) == stub1);
    assert(m.GetInstance(2) == stub2);
    assert(m.GetInstance(3) == stub3);
    assert(m.GetInstance(4) == stub4);
}

void test_pool_hole() {
    start_test();
    StubStubIfs1Manager m;

    msg("Test a pool that have a hole and grow");
    StubIfs1* stub0 = new StubIfs1;
    StubIfs1* stub1 = new StubIfs1;
    delete stub1;

    StubIfs1* stub2 = new StubIfs1;
    StubIfs1* stub3 = new StubIfs1;
    StubIfs1* stub4 = new StubIfs1;

    assert(m.GetInstance(0) == stub0);
    assert(m.GetInstance(1) == 0);
    assert(m.GetInstance(2) == stub2);
    assert(m.GetInstance(3) == stub3);
    assert(m.GetInstance(4) == stub4);

    msg("Using stub to verify access of values via manager");
    Ifs1* sut = stub3;
    sut->run();
    assert(m.GetInstance(3)->GetStub().run().GetCallCounter() == 1);
}

// --- White box testing of init functions ---
void test_init_counters() {
    start_test();
    StubStubIfs1Manager m;
    StubIfs1 stub;

    msg("Increment call counter");
    stub.run();
    assert(stub.GetStub().run().GetCallCounter() > 0);

    msg("Expect call counter is reset to zero");
    StubInternalIfs1::StubInit(&stub.GetStub().run());
    assert(stub.GetStub().run().GetCallCounter() == 0);
}

void test_init_static() {
    start_test();
    StubStubIfs1Manager m;
    StubIfs1 stub;

    stub.GetStub().ifs2_func1_int_char().SetReturn() = 42;
    StubInternalIfs1::StubInit(&stub.GetStub().ifs2_func1_int_char());
    assert(stub.GetStub().ifs2_func1_int_char().SetReturn() == 0);
}

void test_init_callback() {
    start_test();
    StubIfs1 stub;

    stub.GetStub().run().SetCallback(reinterpret_cast<StubCallbackIfs1::Irun*>(42));
    StubInternalIfs1::StubInit(&stub.GetStub().run());
    assert(stub.GetStub().run().GetCallback() == 0);
}
// --- End testing of init functions ---

void test_call_counter() {
    start_test();
    StubStubIfs1Manager m;
    StubIfs1 stub;
    Ifs1* obj = &stub;

    msg("Counter is initialized to zero");
    assert(stub.GetStub().run().GetCallCounter() == 0);
    assert(stub.GetStub().ifs2_func1_int_char().GetCallCounter() == 0);

    msg("Calling func with no params via the interface ptr");
    obj->run();
    assert(stub.GetStub().run().GetCallCounter() > 0);

    msg("Calling func with parameters via the interface ptr");
    obj->ifs2_func1(42, 'x');
    assert(stub.GetStub().ifs2_func1_int_char().GetCallCounter() > 0);
}

void test_call_counter_reset() {
    start_test();
    StubStubIfs1Manager m;
    StubIfs1 stub;
    Ifs1* obj = &stub;

    msg("Calling func with no params via the interface ptr");
    obj->run();
    assert(stub.GetStub().run().GetCallCounter() > 0);

    msg("Reset counter");
    stub.GetStub().run().ResetCallCounter();
    assert(stub.GetStub().run().GetCallCounter() == 0);
}

void test_static_return() {
    start_test();
    StubStubIfs1Manager m;
    StubIfs1 stub;
    Ifs1* obj = &stub;

    stub.GetStub().ifs2_func1_int_char().SetReturn() = 42;
    assert(obj->ifs2_func1(42, 'x') == 42);
}

void test_static_param_stored() {
    start_test();
    StubStubIfs1Manager m;
    StubIfs1 stub;
    Ifs1* obj = &stub;

    obj->ifs2_func1(42, 'x');
    assert(stub.GetStub().ifs2_func1_int_char().GetParam_x0() == 42);
    assert(stub.GetStub().ifs2_func1_int_char().GetParam_x1() == 'x');
}

class TestCallback : public StubCallbackIfs1::Irun,
                     public StubCallbackIfs1::Iifs2_func1_int_char,
                     public StubCallbackIfs1::Iget_ifc3 {
public:
    TestCallback() : called(false), x0(0), x1(0) {}
    ~TestCallback() {}

    void run() { called = true; }
    bool called;

    int ifs2_func1_int_char(int v, char c) {
        x0 = v;
        x1 = c;
        return 42;
    }
    int x0;
    char x1;

    Ifs3& get_ifc3() { return ifs3_inst; }
    StubIfs3 ifs3_inst;
};

void test_callback_simple() {
    start_test();
    StubStubIfs1Manager m;
    TestCallback cb;
    StubIfs1 stub;
    Ifs1* obj = &stub;

    // Configure stub with callback
    stub.GetStub().run().SetCallback(&cb);
    assert(cb.called == false);

    msg("Expecting a callback and thus changing callback objects variable called to true");
    obj->run();
    assert(cb.called == true);

    msg("Expect call counter to increment even though a callback was used");
    assert(stub.GetStub().run().GetCallCounter() > 0);
}

void test_callback_params() {
    start_test();
    StubStubIfs1Manager m;
    TestCallback cb;
    StubIfs1 stub;
    Ifs1* obj = &stub;

    // Configure stub with callback
    stub.GetStub().ifs2_func1_int_char().SetCallback(&cb);

    msg("Callback func with params");
    assert(obj->ifs2_func1(8, 'a') == 42);
    assert(cb.x0 == 8);
    assert(cb.x1 == 'a');

    msg("Expect call counter to increment even though a callback was used");
    assert(stub.GetStub().ifs2_func1_int_char().GetCallCounter() > 0);
}

void test_callback_return_obj() {
    start_test();
    StubStubIfs1Manager m;
    TestCallback cb;
    StubIfs1 stub;
    Ifs1* obj = &stub;

    // Configure stub with callback
    stub.GetStub().get_ifc3().SetCallback(&cb);

    msg("Callback returning obj via ref");
    Ifs3& i3 = obj->get_ifc3();
    i3.dostuff();

    msg("Expect call counter to increment even though a callback was used");
    assert(stub.GetStub().get_ifc3().GetCallCounter() > 0);

    msg("Expect call counter in returned objects to increment");
    assert(cb.ifs3_inst.GetStub().dostuff().GetCallCounter() > 0);
}

int main(int argc, char** argv) {
    std::cout << "functional testing of stub of Ifs1" << std::endl;

    test_stack_instance();
    test_heap_instance();
    test_pool();
    test_pool_delete();
    test_pool_growth();
    test_pool_hole();
    test_init_counters();
    test_init_static();
    test_init_callback();
    test_call_counter();
    test_call_counter_reset();
    test_static_return();
    test_static_param_stored();
    test_callback_simple();
    test_callback_params();
    test_callback_return_obj();

    return 0;
}
