# Domain-Driven Design

DDD as I actually use it, not as the textbook tells it.

## Bounded contexts

The most useful idea. The same word means different things in different parts of the business — "Customer" in billing isn't the same entity as "Customer" in support. Mapping those boundaries explicitly avoids the worst kind of long-running confusion. A monolith with two clear bounded contexts is more maintainable than five microservices with leaky terminology.

## Aggregates

A consistency boundary. The aggregate root is the only thing the outside world references; internal entities are private. The rule "save a whole aggregate in one transaction" forces you to draw the boundary deliberately — too big and it becomes a contention bottleneck, too small and you lose the invariant the aggregate was supposed to protect.

## Value objects vs entities

Entities have identity ("this customer with id 42"). Value objects are defined entirely by their attributes ("the address 123 Main St"). Confusing the two is a perennial source of bugs — money is a classic value object that people accidentally model as an entity, then have weird joins to look up its display format.

## Anti-corruption layers

When integrating with a legacy system or third-party API whose model is wrong for your domain, build a thin layer that translates. Don't let their concepts leak into your core. The team I learned this from kept a `Vendor.swift` file as a literal anti-corruption layer — every external concept entered the codebase through there or not at all.

## What I don't use

Event sourcing for everything. CQRS as default. The full-blown DDD ceremony is overkill for most applications; the language and the boundary tools are the parts that earn their keep.
