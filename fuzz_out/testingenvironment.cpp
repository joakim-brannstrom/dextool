#include "testingenvironment.hpp"
#include "mt1337.hpp"

#include <iostream>
#include <stdio.h>
#include <string.h>
#include <string>
#include <iomanip> 
#include <vector>
#include <sstream>
#include <map>
#include <fstream>

using namespace std;

TestingEnvironment::parameters TestingEnvironment::params = {};
int TestingEnvironment::progress = 0;
vector<RandomGenerator*> TestingEnvironment::generators;
map<string, map<string, vector<vector<int>>>> TestingEnvironment::namespaces;

TestingEnvironment::TestingEnvironment() {}

bool TestingEnvironment::init() {    
    vector<unsigned char> afl_data;
    unsigned char c;
    while (!cin.eof() && !cin.bad()) {
        afl_data.push_back(cin.get());
    }

    //First byte tells us the length of afl_data, check if it's correct

    if ( afl_data.size() < sizeof(unsigned char) + sizeof(unsigned int)*2
	 ||  afl_data.size()-2 != afl_data[0])
    {
	    return false;
    }
    
    //randtype should always be second byte of afl_data
    TestingEnvironment::params.randtype = (unsigned char)afl_data[1];
    

    /* Cycles should contain a amount of bytes read from afl_data.
       The amount is specified by the first byte of the cycles range.
       The first byte of cycles range is found in afl_data[2].
     */
    if (afl_data[0] < 3)
	return false;
    unsigned char CYCLES_MAX_BYTES = afl_data[2];
    unsigned int cycles;

    int offset = 3;
    if (CYCLES_MAX_BYTES > 50 || CYCLES_MAX_BYTES+offset > afl_data[0])
	return false;
    for (int i = 0; i < CYCLES_MAX_BYTES ; i++) {
        cycles += afl_data[offset + i]; //CRASH
    }

    TestingEnvironment::params.cycles = cycles;
    
    /* Seed should contain a amount of bytes read from afl_data.
       The amount is specified by the first byte of the seed range.
       The first byte of seed range is found in afl_data[3 + CYCLES_MAX_BYTES].
     */
    unsigned char SEED_MAX_BYTES = afl_data[3+CYCLES_MAX_BYTES]; //63
    unsigned int seed;

    offset = 3 + CYCLES_MAX_BYTES + 1;
    if (SEED_MAX_BYTES > 50 || SEED_MAX_BYTES+offset >= afl_data[0])
	return false;
    for (int i = 0; i < SEED_MAX_BYTES ; i++) {
       
        seed += afl_data[offset + i];
    }

    TestingEnvironment::params.seed = seed;
    afl_data.clear();

    return true;
}

void TestingEnvironment::quit()
{
    for (unsigned int i = 0; i < generators.size(); ++i)
    {
	delete generators[i];
    }
    generators.clear();
}

void TestingEnvironment::readConfig() {
    ifstream config;
    config.open("../config.txt");

    if (!config.is_open() || config.fail()) {
	return;
    }

    stringstream ss;
    string line;

    while(std::getline(config, line))
    {
	ss << line;
    }

    string ns, var;
    int min_cycles, max_cycles, val;

    while(!ss.bad() && !ss.eof()) {
	ss >> ns;
	ss >> var;
	ss >> min_cycles;
	ss >> max_cycles;
	ss >> val;

	vector<int> vec;
	vec.push_back(min_cycles);
	vec.push_back(max_cycles);
	vec.push_back(val);
	TestingEnvironment::namespaces[ns][var].push_back(vec);
    }
	
    config.close();
}

unsigned int TestingEnvironment::getSeed() {
    return params.seed;
}

unsigned int TestingEnvironment::getCycles() {
    return params.cycles;
}

char TestingEnvironment::getRandType() {
    return params.randtype;
}

const map<string, map<string, vector<vector<int>>>> &TestingEnvironment::getConfig() {
    return namespaces;
}

RandomGenerator& TestingEnvironment::createRandomGenerator() {
    RandomGenerator* rng = new MT1337 (params.seed);
    progress++;
    for (int i = 0; i < progress; ++i)
    {
	rng->nextSeed();
    }
    generators.push_back(rng);
    return *rng;
}
