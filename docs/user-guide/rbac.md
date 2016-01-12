---
title: Role Based Access Control
markdown2extras: wiki-tables
---

# Role Based Access Control and Manta

Beginning with Manta 1.3,
Role Based Access Control (RBAC) lets you limit access
to Manta objects
to other members of your organization.


# Overview

Role Based Access Control is made up of four elements:

* Roles
* Users
* Policies
* Resources

We'll take them from the bottom up to see how they fit together.

**Resources** are the things you want to grant access to.
In Manta resources are Manta objects.

**Policies** are lists of rules that describe access to resources.
The rules are written in a human readable language
that describes the action that is allowed
and the context in which that rule is valid.

The default policy for all objects is to deny access always.
Rules are written in terms of what is allowed.
For example, the following rules say that
getting a Manta object and listing a Manta directory is allowed:

    CAN getobject
    CAN getdirectory


**Users** are login credentials that are associated with your Joyent Cloud
account. While each user name must be unique within an account,
user names do not need to be globally unique.

If there is a Joyent Cloud account named `bigco`
and another one named `littleco`,
both can have a user named `contractor`.

Manta tools use the following environment variables
to make working with accounts and users easier.

* `MANTA_USER` is the account owner.
* `MANTA_SUBUSER` is a user within the account.


**Roles** bring users, policies, and resources together.
Roles are lists of users and
lists of policies.
To allow access to a resource,
you associate, or tag, a resource with a role.


When a user wants to access a resource,
the access system checks whether the user
belongs to a role associated with the resource.
If so, the access system checks the policies
associated with the role
to determine whether the user can access the resource.

The account owner always has complete access to every resource in the account.


# Learning More About Access Control

To learn more see the main [RBAC documentation](https://docs.joyent.com/jpc/rbac).

If you want a quick walkthrough of how access control works with Manta,
see [Getting Started With Access Control](https://docs.joyent.com/jpc/rbac/quickstart).

