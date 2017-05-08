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
map<string, map<string, vector<vector<int> > > > TestingEnvironment::namespaces;

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
    unsigned char CYCLES_MAX_BYTES = afl_data[2];
    unsigned int cycles;

    if (CYCLES_MAX_BYTES > 50)
	return false;

    int offset = 3;
    for (int i = 0; i < CYCLES_MAX_BYTES ; i++) {
        cycles += afl_data[offset + i];
      
    }

    TestingEnvironment::params.cycles = cycles;
    
    /* Seed should contain a amount of bytes read from afl_data.
       The amount is specified by the first byte of the seed range.
       The first byte of seed range is found in afl_data[3 + CYCLES_MAX_BYTES].
     */
    unsigned char SEED_MAX_BYTES = afl_data[3+CYCLES_MAX_BYTES];
    unsigned int seed;

    offset = 3 + CYCLES_MAX_BYTES + 1;
    if (SEED_MAX_BYTES > 50)
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
    config.open("flat/config.txt");

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

	vector<int> vec = {min_cycles, max_cycles, val};
	TestingEnvironment::namespaces[ns][var].push_back(vec);
    }
    /*
      for (auto it : namespaces) {
      std::cout << it.first << " contains: " << std::endl;
      for (auto iter : it.second) {
      std::cout << iter.first << " =>";
      for (auto vec : iter.second) {
      std::cout << " {";
      for (auto i : vec) {
      std::cout << " " << i; 
      } 
      std::cout << "}";
      }
      std::cout << std::endl;
      }
      std::cout << std::endl;
      }*/
    
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

const map<string, map<string, vector<vector<int> > > > &TestingEnvironment::getConfig() {
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
