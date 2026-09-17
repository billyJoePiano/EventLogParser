/**
 * Populates a sandbox with CRT test users, using data in the static resource CRTUsers.
 * CRTUserRefresher.populateFromStaticResource() should be idempotent, and will add any missing PS/PSG/Group assignments to existing users.
 * However, it does NOT remove extraneous assignments from existing users which are not included in the static resource.
 */
public without sharing class CRTUserRefresher {
    public static final String STATIC_RESOURCE_NAME = 'CRTUsers';
    public static final String STATIC_RESOURCE_DESCRIPTION = 'Test Users for Copado Robotic Testing, used to create the test users after Sandbox refreshes.  See Apex class CRTUserRefresher';

    @TestVisible
    private static Boolean logAfterPopulate = true; // for testing purposes only

    @Future(callout=true)
    public static void updateStaticResourceAsync() {
        updateStaticResource();
    }

    public static StaticResourceUtil.Result updateStaticResource() {
        try {
            Set<Id> userIds = new Set<Id>();
            for (GroupMember gm : [SELECT UserOrGroupId FROM GroupMember WHERE Group.DeveloperName = 'CRT_Test_Users' WITH SYSTEM_MODE]) {
                userIds.add(gm.UserOrGroupId);
            }
            List<User> users = [SELECT Username, FirstName, LastName, Email, Alias, TimeZoneSidKey, LocaleSidKey, EmailEncodingKey, LanguageLocaleKey,
                                Profile.Name, UserRole.DeveloperName,
                                (
                                    SELECT PermissionSet.Name, PermissionSet.PermissionSetGroup.DeveloperName
                                    FROM PermissionSetAssignments
                                    WHERE NOT (PermissionSet.IsOwnedByProfile = TRUE)
                                    ORDER BY PermissionSet.PermissionSetGroup.DeveloperName ASC, PermissionSet.Name ASC
                                )
                                FROM User
                                WHERE Id IN :userIds
                                WITH SYSTEM_MODE
                                ORDER BY Username ASC];
            
            Map<Id, List<String>> groupMemberships = new Map<Id, List<String>>();
            for (GroupMember gm : [SELECT UserOrGroupId, Group.DeveloperName FROM GroupMember WHERE UserOrGroupId IN :userIds WITH SYSTEM_MODE ORDER BY Group.DeveloperName ASC]) {
                List<String> userGroupList = groupMemberships.get(gm.UserOrGroupId);
                if (userGroupList == null) {
                    userGroupList = new List<String>();
                    groupMemberships.put(gm.UserOrGroupId, userGroupList);
                }
                userGroupList.add(gm.Group.DeveloperName);
            }
            
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            
            for (User u: users) {
                // remove sandbox identifier from end of username
                List<String> usernameSplit = u.Username.split('\\.');
                usernameSplit.remove(usernameSplit.size() - 1);
                u.Username = String.join(usernameSplit, '.');
                
                //clean-up Profile identifier
                Map<String, Object> untypedUser = StaticResourceUtil.stripFields(u, new List<String> {'ProfileId', 'UserRoleId'});
                Object userProfile = untypedUser.get('Profile');
                if (userProfile != null) {
                    StaticResourceUtil.stripFields((Map<String, Object>)userProfile);
                }
                
                //clean-up Role identifier
                Object userRole = untypedUser.get('UserRole');
                if (userRole != null) {
                    StaticResourceUtil.stripFields((Map<String, Object>)userRole);
                }
                
                //clean-up Permission Set and Permission Set Group identifiers
                Map<String, Object> psas = (Map<String, Object>)untypedUser.get('PermissionSetAssignments');
                if (psas == null) {
                    psas = new Map<String, Object>();
                    psas.put('records', new List<Object>());
                    untypedUser.put('PermissionSetAssignments', psas);
                } else {
                    StaticResourceUtil.stripFields(psas, new List<String> {'done', 'totalSize'});
                    if (psas.get('records') == null) {
                        psas.put('records', new List<Object>());
                    }
                }
                for (Object psaUntyped : (List<Object>)psas.get('records')) {
                    Map<String, Object> psa = (Map<String, Object>)psaUntyped;
                    StaticResourceUtil.stripFields(psa, new List<String> { 'PermissionSetId', 'AssigneeId' });
                    Map<String, Object> ps = (Map<String, Object>)psa.get('PermissionSet');
                    StaticResourceUtil.stripFields(ps, new List<String> {'PermissionSetGroupId'});
                    if (ps.get('PermissionSetGroup') != null) {
                        ps.remove('Name');
                        StaticResourceUtil.stripFields((Map<String, Object>)ps.get('PermissionSetGroup'));
                    }
                }

                //add Public Group memberships (not supported in SObject itself, only in untyped for serialization)
                List<String> userGroupList = groupMemberships.get(u.Id);
                if (userGroupList != null) {
                    untypedUser.put('PublicGroups', userGroupList);
                }

                result.add(untypedUser);
            }
            
            return new StaticResourceUtil('CRTUserRefresher.updateStaticResource')
                .updateJsonStaticResource(STATIC_RESOURCE_NAME, STATIC_RESOURCE_DESCRIPTION, false, Blob.valueOf(JSON.serialize(result)));
            
        } catch (Exception e) {
            Logger.error('CRTUserRefresher.updateStaticResource: ' + STATIC_RESOURCE_NAME + ' EXCEPTION', e);
            Logger.saveLog();
            return new StaticResourceUtil.Result(e);
        }
    }
    
    @Future
    public static void populateFromStaticResourceAsync() {
        populateFromStaticResource();
    }

    public static void populateFromStaticResource() {
        try {
            StaticResource resource = StaticResourceUtil.getStaticResource(STATIC_RESOURCE_NAME);
            if (resource == null) {
                Logger.warn('CRTUserRefresher.populateFromStaticResource: No static resource found named ' + STATIC_RESOURCE_NAME);
                Logger.saveLog();
                return;
            }

            String sandboxName = System.DomainParser.parse(URL.getOrgDomainUrl()).getSandboxName();
            List<Object> usersUntyped = (List<Object>)JSON.deserializeUntyped(resource.Body.toString());
            Set<String> permissionSets = new Set<String>(); // set of all required PermissionSets by Name
            Set<String> permissionSetGroups = new Set<String>(); // set of all required PSGs by DeveloperName
            Set<String> groups = new Set<String>(); // set of all required Groups by DeveloperName
            Map<String, List<String>> permissionSetMemberships = new Map<String, List<String>>(); // username => list of permission sets the user is in
            Map<String, List<String>> permissionSetGroupMemberships = new Map<String, List<String>>(); // username => list of psgs the user is in
            Map<String, List<String>> groupMemberships = new Map<String, List<String>>(); // username => list of public groups the user is in
            
            for (Object untyped : usersUntyped) {
                Map<String, Object> u = (Map<String, Object>)untyped;
                String username = (String)u.get('Username');
                if (username == null) {
                    throw new SerializationException('Missing username');
                } else if (groupMemberships.containsKey(username)) {
                    throw new SerializationException('Duplicate username: ' + username);
                }

                // add sandbox identifier to end of username
                username += '.' + sandboxName;
                u.put('Username', username);

                // remove PermissionSetAssignments since the deserialized child list will be overwritten by an automatic getter-query after upserting the user records
                Map<String, Object> userPsasUntyped = (Map<String, Object>)u.remove('PermissionSetAssignments');
                List<String> userPss = new List<String>();
                List<String> userPsgs = new List<String>();
                if (userPsasUntyped != null) {
                    List<Object> records = (List<Object>)userPsasUntyped.get('records');
                    if (records != null) {
                        for (Object psaUntyped : records) {
                            Map<String, Object> psa = (Map<String, Object>)psaUntyped;
                            Map<String, Object> ps = (Map<String, Object>)psa.get('PermissionSet');
                            Map<String, Object> psg = (Map<String, Object>)ps.get('PermissionSetGroup');
                            if (psg != null) {
                                String psgName = (String)psg.get('DeveloperName');
                                userPsgs.add(psgName);
                                permissionSetGroups.add(psgName);
                            } else {
                                String psName = (String)ps.get('Name');
                                userPss.add(psName);
                                permissionSets.add(psName);
                            }
                        }
                    }
                }
                permissionSetMemberships.put(username, userPss);
                permissionSetGroupMemberships.put(username, userPsgs);

                //remove PublicGroups key, since it is not supported by User SObject (i.e. would throw error during deserialization)
                List<Object> userGroupsUntyped = (List<Object>)u.remove('PublicGroups');
                List<String> userGroups = new List<String>();
                if (userGroupsUntyped != null) {
                    for (Object groupNameUntyped : userGroupsUntyped) {
                        String groupName = (String)groupNameUntyped;
                        userGroups.add(groupName);
                        groups.add(groupName);
                    }
                }
                groupMemberships.put(username, userGroups);
            }

            // re-do deserialization from untyped to typed
            List<User> newUsers = (List<User>)JSON.deserialize(JSON.serialize(usersUntyped), List<User>.class);

            //gather names of needed Profiles and UserRoles
            Set<String> profiles = new Set<String>();
            Set<String> roles = new Set<String>();

            for (User u : newUsers) {
                if (u.Profile != null) {
                    profiles.add(u.Profile.Name);
                }
                if (u.UserRole != null) {
                    roles.add(u.UserRole.DeveloperName);
                }
            }

            // query based on names of needed Profiles, UserRoles, PermissionSets, PermissionSetGroups, and Groups
            Map<String, Id> prfs = new Map<String, Id>(); //Profile.Name => Profile.Id
            Map<String, Id> rls = new Map<String, Id>(); //UserRole.DeveloperName => UserRole.Id
            Map<String, Id> pss = new Map<String, Id>(); // PermissionSet.Name => PermissionSet.Id
            Map<String, Id> psgs = new Map<String, Id>(); // PermissionSet.PermissionSetGroup.DeveloperName => PermissionSet.Id
            Map<String, Id> gs = new Map<String, Id>(); // Group.DeveloperName => Group.Id
            for (Profile prf : [SELECT Id, Name FROM Profile WHERE Name IN :profiles WITH SYSTEM_MODE]) {
                prfs.put(prf.Name, prf.Id);
            }
            for (UserRole rl : [SELECT Id, DeveloperName FROM UserRole WHERE DeveloperName IN :roles WITH SYSTEM_MODE]) {
                rls.put(rl.DeveloperName, rl.Id);
            }
            for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :permissionSets WITH SYSTEM_MODE]) {
                pss.put(ps.Name, ps.Id);
            }
            for (PermissionSet ps : [SELECT Id, PermissionSetGroup.DeveloperName FROM PermissionSet WHERE PermissionSetGroup.DeveloperName IN :permissionSetGroups WITH SYSTEM_MODE]) {
                psgs.put(ps.PermissionSetGroup.DeveloperName, ps.Id);
            }
            for (Group g : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN :groups WITH SYSTEM_MODE]) {
                gs.put(g.DeveloperName, g.Id);
            }

            profiles.removeAll(prfs.keySet());
            roles.removeAll(rls.keySet());
            permissionSets.removeAll(pss.keySet());
            permissionSetGroups.removeall(psgs.keySet());
            groups.removeAll(gs.keySet());
            if (profiles.size() > 0 || roles.size() > 0 || permissionSets.size() > 0 || permissionSetGroups.size() > 0 || groups.size() > 0) {
                throw new SerializationException('Missing Profiles, UserRoles, PermissionSets, PermissionSetGroups, and/or Groups (Public Groups/Queues/etc).'
                                                 + '\nProfiles: ' + JSON.serialize(profiles)
                                                 + '\nUserRoles: ' + JSON.serialize(roles)
                                                 + '\nPermissionSets: ' + JSON.serialize(permissionSets)
                                                 + '\nPermissionSetGroups: ' + JSON.serialize(permissionSetGroups)
                                                 + '\nGroups: ' + JSON.serialize(groups));
            }

            // query already existing users
            Map<Id, User> alreadyExistingUserIds = new Map<Id, User>([SELECT Id, Username FROM User WHERE Username IN :permissionSetMemberships.keySet() WITH SYSTEM_MODE]);
            Map<String, User> alreadyExistingUserNames = new Map<String, User>();

            for (User u : alreadyExistingUserIds.values()) {
                alreadyExistingUserNames.put(u.Username, u);
            }

            // Assign ids for user (if pre-existing), Profile and UserRole
            for (User u : newUsers) {
                User alreadyExisting = alreadyExistingUserNames.get(u.Username);
                if (alreadyExisting != null) {
                    u.Id = alreadyExisting.Id;
                }
                if (u.Profile != null) {
                    u.ProfileId = prfs.get(u.Profile.Name);
                    u.Profile = null;
                }
                if (u.UserRole != null) {
                    u.UserRoleId = rls.get(u.UserRole.DeveloperName);
                    u.UserRole = null;
                }
            }

            // Check PS/PSG and Group assignments for already existing users
            Map<Id, Map<Id, Id>> alreadyExistingPsas = new Map<Id, Map<Id, Id>>(); // Maps User Id => PermissionSet Id => PermissionSetAssignment Id
            Map<Id, Map<Id, Id>> alreadyExistingGms = new Map<Id, Map<Id, Id>>(); // Maps User Id => Group Id => GroupMember Id

            for (PermissionSetAssignment psa : [SELECT Id, PermissionSetId, AssigneeId FROM PermissionSetAssignment WHERE AssigneeId IN :alreadyExistingUserIds.keySet() WITH SYSTEM_MODE]) {
                Map<Id, Id> userMap = alreadyExistingPsas.get(psa.AssigneeId);
                if (userMap == null) {
                    userMap = new Map<Id, Id>();
                    alreadyExistingPsas.put(psa.AssigneeId, userMap);
                }
                userMap.put(psa.PermissionSetId, psa.Id);
            }

            for (GroupMember gm : [SELECT Id, GroupId, UserOrGroupId FROM GroupMember WHERE UserOrGroupId IN :alreadyExistingUserIds.keySet() WITH SYSTEM_MODE]) {
                Map<Id, Id> userMap = alreadyExistingGms.get(gm.UserOrGroupId);
                if (userMap == null) {
                    userMap = new Map<Id, Id>();
                    alreadyExistingGms.put(gm.UserOrGroupId, userMap);
                }
                userMap.put(gm.GroupId, gm.Id);
            }

            // All queries finished.  Now ready to start inserting/updating records
            Database.upsert(newUsers, AccessLevel.SYSTEM_MODE);

            List<PermissionSetAssignment> newPsas = new List<PermissionSetAssignment>();
            List<GroupMember> newGms = new List<GroupMember>();
            
            for (User u : newUsers) {
                Map<Id, Id> userMap = alreadyExistingPsas.get(u.Id);
                for (String psName : permissionSetMemberships.get(u.Username)) {
                    Id psId = pss.get(psName);
                    if (userMap == null || userMap.get(psId) == null) {
                        newPsas.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId));
                    }
                }
                for (String psgName : permissionSetGroupMemberships.get(u.Username)) {
                    Id psId = psgs.get(psgName);
                    if (userMap == null || userMap.get(psId) == null) {
                        newPsas.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId));
                    }
                }

                userMap = alreadyExistingGms.get(u.Id);
                for (String groupName : groupMemberships.get(u.Username)) {
                    Id groupId = gs.get(groupName);
                    if (userMap == null || userMap.get(groupId) == null) {
                        newGms.add(new GroupMember(GroupId = groupId, UserOrGroupId = u.Id));
                    }
                }
            }

            Database.insert(newPsas, AccessLevel.SYSTEM_MODE);
            Database.insert(newGms, AccessLevel.SYSTEM_MODE);

            List<SObject> allRecords = new List<SObject>();
            allRecords.addAll(newUsers);
            allRecords.addAll(newPsas);
            allRecords.addAll(newGms);

            if (logAfterPopulate) {
                Logger.info('CRTUserRefresher.populateFromStaticResource: success adding/updating users')
                    .setRecord(allRecords);
                Logger.saveLog();
            }

        } catch (Exception e) {
            Logger.error('CRTUserRefresher.populateFromStaticResource: EXCEPTION', e);
            Logger.saveLog();
            throw e;
        }
    }
}