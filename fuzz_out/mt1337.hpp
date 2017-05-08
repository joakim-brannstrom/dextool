#ifndef MT1337_H
#define MT1337_H

#include "randomgenerator.hpp"

using namespace std;

class MT1337 : public RandomGenerator {
    long long mt[624];
    int index;
    
    long long extractNumber();
    void twistIt();
    long long generateRangeValue(const long long &min, const long long &max);
public:
    MT1337(const unsigned int seed);
    long long generate();
    long long generate(long long min, long long max);
    long long generate(const map<string, vector<vector<int> > > &vars, string name, const int64_t &curr_cycles);
    long long generate(const map<string, vector<vector<int> > > &vars, string name, long long min, long long max, const int64_t &curr_cycles);
    uint64_t getSeed();
    void nextSeed();
    void generateClients(vector<string> &clients, const int &max);
};

#endif
