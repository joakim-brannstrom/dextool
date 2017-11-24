import scriptlike;

void main()
{
	auto name = userInput!string("Please enter your name");
	auto age = userInput!int("And your age");

	if(userInput!bool("Do you want to continue?"))
	{
		string outputFolder = pathLocation("Where you do want to place the output?");
		auto color = menu!string("What color would you like to use?", ["Blue", "Green"]);
	}

	auto num = require!(int, "a > 0 && a <= 10")("Enter a number from 1 to 10");

	pause(); // Prompt "Press Enter to continue...";
	pause("Hit Enter again, dood!!");
}
