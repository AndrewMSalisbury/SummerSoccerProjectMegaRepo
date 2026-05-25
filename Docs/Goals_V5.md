**Goals for the Summer**
The number one goal for the summer is to work on my understanding agentic coding and my ability to understand what good code truly is. The proof for this will be if I can read AI-generated code, spot where it's wrong, and redirect it. I want to develop skills that will be useful both for future personal projects, but also to future employers, namely knowledge of programming and a project to show as proof of this understanding. Beyond that, I want to see if my personal theory about coaches is right, and if my intuition that there is something deeper here is correct, as the I think that intuition will be invaluable if I can work in sports analytics.

**Project Goal**
The end goal of this project is to create a model that ranks all coaches possible by way of a defensible analytical result and gathers a variety of data that would be useful for teams for hiring decisions into one place.

**The Hypothesis**
 A team's minutes-weighted squad value predicts final points more accurately than raw squad value. The residual, performance above or below expectation, is partly attributable to coaching quality. We expect coaches who consistently produce positive residuals across multiple teams to be identifiably better. We will attempt to assign coaches some value to be added to our model, which can improve our model's performance, showing the rough theory is correct.

**How We'll Know We Succeeded**
We'll know we succeeded if we have either developed a working way to rank coaches, defined by if our additional coaching variable can significantly reduce the variation (Rough hope of 25% reduction in variation) from our model to actual results, or if we have sufficiently disproven (failure to improve the model) my hypothesis, and done work to craft a new hypothesis that works towards the same goal.

**Risks**
As mentioned in the hypothesis document, there are various risks and issues involved with the current hypothesis.
Risk 1: The assumption that coaches cause variation
Potential solution: analyze coaches particularly when they switch teams, as that will be the time when their impact is most obvious due the the changing of their environment.
Risk 2: The Ceiling
Potential solution: Change the way we build our model from rank in the league to points, enabling top coaches to still outperform.
Risk 3: Data Availability
Potential solution: Identify a source for coach-team-season assignments and add it to the data layer.