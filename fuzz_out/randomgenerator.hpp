#ifndef RANDOMGENERATOR_HPP
#define RANDOMGENERATOR_HPP

#include <stdint.h>
#include <string>
#include <map>
#include <vector>

using namespace std;

class RandomGenerator
{
public:
    /*
      Constructor
     */
    RandomGenerator() = default;

    /*
      Virtual destructor
     */
    virtual ~RandomGenerator() {};

    /*
      Generates random value
     */
    virtual long long generate() = 0;

    /*
      Generates random value within min and max range
     */
    virtual long long generate(long long min, long long max) = 0;
    
    /*
      Generates static value
     */
    virtual long long generate(const map<string, vector<vector<int> > > &vars, string name, const int64_t &curr_cycles) = 0;

    /*
      Generates static value for variables using ranges
     */
    virtual long long generate(const map<string, vector<vector<int> > > &vars, string name, long long min, long long max, const int64_t &curr_cycles) = 0;

    /*
      Gets the current seed value.
     */
    virtual uint64_t getSeed() = 0;

    /*
      Moves the random generator to the next state, updating the seed.
     */
    virtual void nextSeed() = 0;
    
    virtual void generateClients(vector<string> &clients,  const int &max) = 0;

protected:
    string name;
};

#endif
