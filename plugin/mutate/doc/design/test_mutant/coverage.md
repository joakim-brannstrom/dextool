# <a name="uc-coverage"></a> Coverage

The user wants to speed up mutation testing by using coverage to tag all
mutants that are not covered as alive.

## <a name="design-coverage"></a> Design

To keep it simple only entry point coverage is gathered. It is when a function
is entered. It is fast and easy to implement.

## Coverage Map File

The file format for the shared memory file has the first byte as the signal
that the tests have actually executed. The information is only used if this
first byte is `1`. The following bytes position is internally mapped by the
plugin to a code region. Thus the position and its meaning is runtime
generated.
