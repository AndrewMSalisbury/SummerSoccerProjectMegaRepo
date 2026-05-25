# Coach Valuation Project — Getting Started

This summer you're going to take your existing R model — the one that roughly validates the idea that European football coaches are mispriced — and make it robust, predictive, and trustworthy. You built the first version by hand. Now you'll refine it, and learn to work with an AI agent as a real collaborator while you do.

This doc isn't a plan. **Building the plan is your first job.** What follows is the handful of things worth knowing before you start, and then the questions you'll answer to design your own summer. Bring me what you come up with and we'll sharpen it together.

---

## What this summer is for

The project, improving the coach model, is what you'll spend the summer doing. But it isn't really *why*. The way I've structured this reflects two things I'm hoping you get out of the summer that go beyond just making the model better, and you should know what they are so we can agree on them or push back on them.

The first is about where finance is going. Standard analyst work, the kind where someone hands you a question and you produce the analysis, is increasingly being done by agents, and that's accelerating. But the same forces are sharpening the premium on a different kind of analyst: the one who can take a view, build a thesis, stress-test it honestly, and stake a position on the result. That's the disposition that's going to be rare and well-paid five to seven years from now, and it's a different skill than churning out analyses on demand. This project happens to look exactly like that kind of work: spot a possible market mispricing, build a case, try to break it, produce a finding you'd stake your name on. So the question for the summer isn't just "is the model better" but "are you sharper as the kind of analyst who can do that."

The second is about working with the agent itself. Not the tool per se, but the judgment of when to lean on it, when to direct it, when to distrust it and do the thinking yourself. That working skill is probably the most generally valuable thing you can build this summer. It carries into anything information-shaped you'll do for the rest of your career, finance or otherwise. The model is the vehicle. The way you learn to work alongside the agent is what you'll actually take away.

These are my goals, not yours yet. You should have your own. Before you start designing the work, I want you to think about what *you* want the summer to have produced. A portfolio piece, a publishable result, a specific skill set, something concrete to talk about in interviews, whatever it actually is for you. Bring me what you've got. We'll land on a shared set, write them down, and plan against them.

---

## A few things worth knowing up front

These are the things I'd save you from having to rediscover. Everything else — how to structure the work, what to build first, how to scope it — is yours to figure out.

**Work with the agent plan-first.** The natural instinct is to ask the agent to write code and then review the code. That's backwards. Reviewing generated code is slow and easy to skip; reviewing a clear plan is fast and catches problems before they're baked in. So for any real piece of work: think it through *with* the agent first and write a short plan — what you're changing, why, the approach, what could go wrong, how you'll know it worked. Get the plan right, to the point where you'd stand behind every line of it. *Then* let the agent implement. The plan is where your judgment lives; the code is just the plan compiled. (This feels slower than diving into code. It isn't — it saves you from building the wrong thing and having to unwind it.)

**The repo is your shared workspace with the agent.** Anything the agent should know about your project (what it is, what you're trying to do, the plans you and it have agreed on, the decisions you've made) needs to live in the repo as a file. Not in chat history (chat doesn't persist; the next session starts cold), not in a notebook on your desk. The agent reads what's in the repo; that's its memory. So your planning folder lives alongside the code, this orientation doc gets committed as the first thing in there, and every plan you iterate on with the agent ends up as a file you can point at.

**Your existing code is an asset, and that changes how you proceed.** A few principles for working on code that already works:
- Get it safely under version control before you change anything. You want to always be able to return to the version that worked.
- You can't safely refactor code you can't verify. "It still roughly validates the theory" isn't verification. Figure out how to lock in what the current model produces *before* you start cleaning it, so you can tell whether a change preserved the behavior you meant to keep or quietly broke something. (Worth asking the agent about "characterization testing" — it's the standard technique for exactly this situation.)
- It works in R. Don't let the agent talk you into rewriting it in another language; that's effort spent re-creating what you already have. Improve it in place.

**Be willing to attack your own conclusion.** You built this, you want it to work, and it roughly does — which makes it dangerously easy to "improve" it in ways that protect your result instead of testing it. Do the opposite. Try hard to break your own finding: is the coach effect real, or is it mostly that good coaches get hired by good teams anyway, or just noise from small samples? If it's real, it'll survive your best attempt to kill it — and then you'll actually believe it, and so will anyone you show it to.

**One question to keep asking yourself, constantly:** *how do I know that's right?* The agent will almost never ask it for you. In this kind of analysis the default state of any result is plausible-but-wrong. The habit of interrogating a result before trusting it is the most important one you'll build all summer.

---

## Before you start: getting set up

You haven't used the agent before, and getting it installed and connected to a working repo is faster done together than read from a doc, so we'll sit down and do that part. A few pieces need to be in place before you start the real work:

- The agent (Claude Code) installed and working on your laptop.
- A new project repo on GitHub that you own, with me added as a collaborator so I can see what you commit. (This doc you're reading is the first thing that goes in.)
- Your existing R model pulled into the new repo and tagged as the baseline, before you touch anything.
- A short `CLAUDE.md` in the repo: what the project is, what you're trying to do, the conventions you want to follow. Write that one yourself, with the agent if you want a sounding board. Putting the project into your own words is itself a useful first exercise.

---

## Your first task: design the summer

Before any coding, I want you to propose how you'll spend it. Use the agent as a thinking partner for this — planning the work is itself the first and best exercise in the plan-first habit above.

The very first piece, before any milestones or sequencing, is what you're actually trying to accomplish. I named my two goals above; you'll have your own. The first artifact in your planning folder is a short doc capturing the shared set we agree on, and for each goal what evidence of progress would look like by the end of the summer. That doc is what the whole project gets evaluated against, not just whether the model improved. Bring it to me before you draft milestones; we'll land on it together, and *then* you plan the work against it.

A few things to think through as you build that plan. These are prompts, not a checklist — work them out with the agent, and write down your answers and your reasoning:

**Understand what you already have.** What does your current model actually do, end to end? What exactly does it produce right now? Where are the shortcuts, the parts you weren't sure about, the things you'd want to shore up? (Having the agent read your code and document it is a good way to start — and a good first taste of the workflow.)

**Define what you're actually trying to improve.** Mike proposed "more robust and more predictive." Is that even right? What do those mean concretely enough that you could tell whether you'd succeeded? What would "robust" look like — and how would you measure "predictive"? If you can't measure "better," you won't know if a change helped.

**Pressure-test the idea itself.** What's the strongest case that you're wrong? What could explain the residual you're attributing to coach skill, *besides* coach skill? Who would actually use this analysis, and what decision are they making? (That last one shapes what the final output should even be.)

**Then turn that into a plan.** What's the sequence of work? What does a first improved version look like versus what you'd save for later? What would you want to have finished such that, even if the rest didn't happen, the summer was clearly worth it?

A good milestone, by the way, has three properties: it's something *complete* (not "work on the model" but "a model that does X"), it's *valuable on its own* (if you stopped right after it, you'd still have something worth showing), and it's *verifiable* (you can tell when you've actually hit it). Aim for milestones like that, and order them so the surest, most foundational wins come first and the ambitious stretches come later.

**The calendar you're planning around:** you're home May 24, away June 23–July 3, back to school August 16. That's the container. How you fill it is yours to propose.

---

## As you go

Keep a running log of the decisions you make and why — including the ones where you and the agent disagreed and how you settled it. By the end of the summer that log is as much the product as the model is; it's the record of how you learned to work.

For the planning documents themselves, you'll want some structure so they don't become an unnavigable pile — but figure out a scheme that works for you. (If you want a starting point to react to: one folder per phase, numbered files inside, and a single index file listing every plan with a one-line summary and its status. The index is what actually keeps things findable. But make it yours.)

When you've got a draft plan, bring it to me. I won't be writing it for you — my job is to ask the questions that make your plan better.
