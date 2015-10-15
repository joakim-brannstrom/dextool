#ifndef VARIABLES_H
#define VARIABLES_H

int a;
extern int b;

/* a duplicate, expecting it to be ignored */
extern int b;

extern const int c;
#endif // VARIABLES_H
