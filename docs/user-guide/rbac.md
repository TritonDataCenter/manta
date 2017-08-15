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


**Users** are login credentials that are associated with your Triton
account. While each user name must be unique within an account,
user names do not need to be globally unique.

If there is a Triton account named `bigco` and another one named `littleco`,
both can have a user named `contractor`.

Manta tools use the following environment variables
to make working with accounts and users easier.

* `MANTA_USER` is the account owner.
* `MANTA_SUBUSER` is a user within the account.


**Roles** bring users, policies, and resources together.
Roles define what users can do with a resource. For example, a role
containing a policy with the `CAN getobject` action enables the members
of the role to make `GET` object requests.

To allow the access to a specific resource,
you also need to associate, or tag, the resource with a role and add
authorized users as members of the role. You can tag or untag roles
for a resource by updating the 'role-tag' attribute value in the
object metadata. See the [mchmod](https://apidocs.joyent.com/manta/mchmod.html)
or [mchattr](https://apidocs.joyent.com/manta/mchattr.html) CLI reference for
an example of updating object role tags or updating metadata in general.

Roles can be tagged to directories as well (the only exception is the root
directory of the account). Directory access allows the user to list the objects
in it but does not imply permissions for objects in it. This is different from
the POSIX filesystems. In other words,
- Roles on the directory are not required to access objects in that directory
  or to list the contents of subdirectories.
- Roles tagged on a directory are not automatically cascaded to the objects or
  subdirectories within the directory.

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

If you are already familiar with the key RBAC concepts, you can review the
complete list of [Manta Actions](https://docs.joyent.com/public-cloud/rbac/rules#manta-actions)
and start defining the rules for your RBAC policies.
