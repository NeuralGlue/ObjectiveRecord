//
//  ActiveRecord
//  Shopify_Mobile
//
//  Created by Matthew Newberry on 7/22/10.
//  Copyright 2010 Shopify. All rights reserved.
//

#import "ActiveRecord.h"
#import "ObjectiveRecord+Utilities.h"
#import "ActiveRequest.h"


@implementation ActiveRecord : NSManagedObject 

@synthesize delegate = _delegate;
@synthesize remoteDidFinishSelector = _remoteDidFinishSelector;
@synthesize remoteDidFailSelector = _remoteDidFailSelector;

#pragma mark -
#pragma mark Utilities

+ (void) save{
	
	[[self activeManager].managedObjectContext save];
}

- (ActiveRecord *) save{
	
	[[[self class] activeManager].managedObjectContext save];
	
	return self;
}

+ (ActiveManager *) activeManager{
	
	ActiveManager *manager = [ActiveManager shared];
	[manager.defaultDateParser setDateFormat:[self dateFormat]];
	
	return manager;
}

+ (NSManagedObjectContext *) managedObjectContext {
	
    return [[self activeManager] managedObjectContext];
}

+ (NSString *) entityName {
	
	NSString *name = $S(@"%@", self);
		
	if(![self shouldParseEntityNameFromRelationships] || ![self hasRelationships])
		return name;
	
	NSMutableString *tempName = [NSMutableString stringWithString:name];
	
	for(NSString *key in [self relationshipsByName]){
				
		NSRange search = [name rangeOfString:key options:NSCaseInsensitiveSearch];
		if(search.location != NSNotFound){
			
			[tempName deleteCharactersInRange:search];
		}
	}
	
	return tempName;
}

+ (NSEntityDescription *) entityDescription{
	
	return [NSEntityDescription entityForName:$S(@"%@", self) inManagedObjectContext:[self managedObjectContext]];
}

- (NSMutableDictionary *) properties {
	
    return [self properties:nil withoutObjects:nil];
}

- (NSMutableDictionary *) properties:(NSDictionary *)options {
	
    return [self properties:options withoutObjects:nil];
}

- (NSMutableDictionary *) properties:(NSDictionary *)options withoutObjects:(NSMutableArray *)withouts {
	
    NSArray *only		= [options objectForKey:@"$only"];
    NSArray *except		= [options objectForKey:@"$except"];
	BOOL relationships	= [options objectForKey:@"$relationships"] == nil ? YES : [[options objectForKey:@"$relationships"] boolValue];
    BOOL serializeDates	= [[options objectForKey:@"$serializeDates"] boolValue];
	
    if (withouts == nil)
        withouts = [NSMutableArray array];
    [withouts addObject:self];
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    for (NSPropertyDescription *prop in [[[self class] entityDescription] properties]) {
        NSString *key = prop.name;
        if ((only == nil || [only containsObject:key]) && (except == nil || ![except containsObject:key])) {
            id value = [self valueForKey:key];
            if (value == nil)
                value = [NSNull null];
						
            // For attributes, simply set the value
            if ([prop isKindOfClass:[NSAttributeDescription class]]) {
                // Serialize dates if serializeDates is set
                if ([value isKindOfClass:[NSDate class]] && serializeDates)
                    value = [[[self class] activeManager].defaultDateParser stringFromDate:value];
								
                [dict setObject:value forKey:key];
            }
			
            else if(relationships){
                NSRelationshipDescription *rel = (NSRelationshipDescription *)prop;
                if ([rel isToMany]) {
                    NSSet *relResources = value;
                    NSMutableArray *relArray = [NSMutableArray arrayWithCapacity:[relResources count]];
                    for (ActiveRecord *resource in relResources) {
                        // Only add objects which are not part of the withouts array
                        // (most importantly, ignore objects that have been previously added)
                        if (![withouts containsObject:resource])
                            [relArray addObject:[resource properties:options withoutObjects:withouts]];
                    }
                    [dict setObject:relArray forKey:key];
                }
                else {
                    if (![withouts containsObject:value])
                        [dict setObject:value forKey:key];
                }
            }
        }
    }
    return dict;
}

+ (NSDictionary *) relationshipsByName {
	
    NSDictionary *rels = [[[self activeManager] modelRelationships] objectForKey:self];
    if (rels == nil) {

        rels = [[self entityDescription] relationshipsByName];
        [[[self activeManager] modelRelationships] setObject:rels forKey:self];
    }
    return rels;
}

+ (BOOL) hasRelationships {
	
    return [[self relationshipsByName] count] > 0;
}

+ (NSDictionary *) attributesByName {
	
    NSDictionary *attr = [[[self activeManager] modelAttributes] objectForKey:self];
    if (attr == nil) {

        attr = [[self entityDescription] attributesByName];
        [[[self activeManager] modelAttributes] setObject:attr forKey:self];
    }
    return attr;
}

+ (NSDictionary *) propertiesByName {
		
    NSDictionary *props = [[[self activeManager] modelProperties] objectForKey:self];
	
    if (props == nil) {
		
        props = [[self entityDescription] propertiesByName];
        [[[self activeManager] modelProperties] setObject:props forKey:self];
    }
	
    return props;
}

+ (NSPropertyDescription *) propertyDescriptionForField:(NSString *)field inModel:(Class)modelClass {
	
    return [[modelClass propertiesByName] objectForKey:field];
}

+ (NSPropertyDescription *) propertyDescriptionForField:(NSString *)field {
	
    return [self propertyDescriptionForField:field inModel:self];
}

+ (NSString *) localNameForRemoteField:(NSString *)name {
    return name;
}

+ (NSString *) remoteNameForLocalField:(NSString *)name {
    return name;
}


#pragma mark -
#pragma mark Finding

+ (NSArray *) all{
	
	ActiveResult *result = [self find:nil];

	return [NSArray arrayWithArray:[result objects]];
}

+ (id) first{
	
	ActiveResult *result = [self find:nil sortBy:nil limit:1 fields:nil];
	
	return [result object];
}

+ (id) last{
	
	NSRange sortRange = [[[self defaultSort] lowercaseString] rangeOfString:@"desc"];
	NSString *sortDir = sortRange.location == NSNotFound ? @"desc" : @"asc";
	
	
	ActiveResult *result = [self find:nil sortBy:[[self defaultSort] stringByReplacingCharactersInRange:sortRange withString:sortDir]];
	
	return [result object];
}

+ (BOOL) exists:(NSNumber *)itemID{
		
	return [self findByID:itemID] == nil ? NO : YES;
}

+ (id) findByID:(NSNumber *) itemID{
	
	return [self findByID:itemID moc:[self managedObjectContext]];
}

+ (id) findByID:(NSNumber *)itemID moc:(NSManagedObjectContext *)moc{
	
	if([self propertyDescriptionForField:[self localIDField]] == nil)
		return nil;
	
	if(!moc)
		moc = [self managedObjectContext];
	
	if(![[self propertiesByName] objectForKey:[self localIDField]])
		return nil;
	
	ActiveResult *result = [self find:$P($S(@"%@ = %i", [self localIDField], [itemID intValue])) sortBy:nil limit:1 fields:$A([self localIDField]) moc:moc];

	return [result object];
}

+ (ActiveResult *) find:(id) query{
    
    return [self find:query sortBy:nil limit:0 fields:nil];
}

+ (ActiveResult *) find:(id) query sortBy:(NSString *)sortBy{
	
	return [self find:query sortBy:sortBy limit:0 fields:nil];
}

+ (ActiveResult *) find:(id) query limit:(int) limit{
	
	return [self find:query sortBy:nil limit:limit fields:nil];
}

+ (ActiveResult *) find:(id) query sortBy:(NSString *)sortBy limit:(int)limit{
    
	return [self find:query sortBy:sortBy limit:limit fields:nil];
}

+ (ActiveResult *) find:(id) query sortBy:(NSString *)sortBy limit:(int)limit fields:(NSArray *)fields{
	
	return [self find:query sortBy:sortBy limit:limit fields:fields moc:[self managedObjectContext]];
}

+ (ActiveResult *) find:(id) query sortBy:(NSString *)sortBy limit:(int)limit fields:(NSArray *)fields moc:(NSManagedObjectContext *)moc{
	
    NSFetchRequest *fetch = [self fetchRequest];
	[fetch setEntity:[self entityDescription]];
	[fetch setPredicate:[ActiveSupport predicateFromObject:query]];
	[fetch setPropertiesToFetch:fields];
	[fetch setFetchBatchSize:20];
	
	if(sortBy != nil)
		[fetch setSortDescriptors:[ActiveSupport sortDescriptorsFromString:sortBy]];
		
	if(limit > 0)
		[fetch setFetchLimit:limit];
	
	NSError *error;
	
	if(!moc)
		moc = [self managedObjectContext];
		
	NSArray *results = [moc executeFetchRequest:fetch error:&error];

	ActiveResult *result = [[[ActiveResult alloc] initWithResults:results] autorelease];

	return result; 
}


#pragma mark -
#pragma mark Utilities
+ (NSFetchRequest *) fetchRequest{
	
	NSFetchRequest *fetch = [[[NSFetchRequest alloc] init] autorelease];
	[fetch setEntity:[self entityDescription]];
	[fetch setSortDescriptors:[ActiveSupport sortDescriptorsFromString:[self defaultSort]]];
	return fetch;
}

+ (int) count{
	
	return [self count:nil];
}

+ (int) count:(NSPredicate *) predicate{
	
	NSFetchRequest *fetch = [self fetchRequest];
	[fetch setPredicate:predicate];
	
	return [[self managedObjectContext] countForFetchRequest:fetch error:nil];
}

+ (NSNumber *) sum:(NSString *)property{
	
	ActiveResult *result = [self find:nil sortBy:nil limit:0 fields:$A(property)];
	
	return [[result objects] valueForKeyPath:$S(@"@sum.%@", property)];
}

+ (NSNumber *) minimum:(NSString *)property{
	
	ActiveResult *result = [self find:nil sortBy:nil limit:0 fields:$A(property)];
	
	return [[result objects] valueForKeyPath:$S(@"@min.%@", property)];
}

+ (NSNumber *) maximum:(NSString *)property{
	
	ActiveResult *result = [self find:nil sortBy:nil limit:0 fields:$A(property)];
	
	return [[result objects] valueForKeyPath:$S(@"@max.%@", property)];
}

+ (NSNumber *) average:(NSString *)property{
	
	ActiveResult *result = [self find:nil sortBy:nil limit:0 fields:$A(property)];
	
	return [[result objects] valueForKeyPath:$S(@"@avg.%@", property)];
}


#pragma mark -
#pragma mark Create / Update

- (NSDictionary *) map{
	
	// Subclass to map fields
	return [NSDictionary dictionary];
}

+ (id) blank{
	
	return [self create:nil];
}

+ (id) create:(id)parameters {
    return [self create:parameters withOptions:[self defaultCreateOptions]];
}

+ (id) create:(id)parameters withOptions:(NSDictionary *)options {
		
    if ([parameters isKindOfClass:[NSArray class]]) {

        NSMutableArray *resources = [NSMutableArray arrayWithCapacity:[parameters count]];
        for (id item in parameters)
            [resources addObject:[self create:item withOptions:options]];
		
        return resources;
    }
    else {
		
		NSManagedObjectContext *moc = [options objectForKey:@"moc"] ? [options objectForKey:@"moc"] : [self managedObjectContext];
		ActiveRecord *resource = [[self alloc] initWithEntity:[self entityDescription] 
							   insertIntoManagedObjectContext:moc];
		
		NSMutableDictionary *dict	= [NSMutableDictionary dictionary];
		NSDictionary *map			= [resource map];
		
		for(NSString *key in [parameters keyEnumerator]){
			
			NSString *mappedKey = [[map allKeys] indexOfObject:key] == NSNotFound ? key : [map objectForKey:key];
			[dict setObject:[parameters objectForKey:key] forKey:[mappedKey stringByReplacingOccurrencesOfString:@"-" withString:@"_"]];
		}
				
        [resource update:dict withOptions:options];		
		[resource willCreate:options];
		        
        if ([[self class] activeManager].logLevel > 1) {
            NSLog(@"Created new %@", self);
            if ([[self class] activeManager].logLevel > 4)
                NSLog(@"=> %@", resource);
        }
        
		SEL createdAtSel = NSSelectorFromString([self createdAtField]);
		if ([resource respondsToSelector:createdAtSel] && [resource valueForKey:[self createdAtField]] == nil)
			[resource setValue:[NSDate date] forKey:[self createdAtField]];
		
        [resource didCreate:options];
		
        return [resource autorelease];
    }
}

+ (id) build:(id)parameters {
	
    return [self build:parameters withOptions:[self defaultCreateOptions]];
}

+ (id) build:(id)parameters withOptions:(NSDictionary *)options {

	id resource;
	
    if ([parameters isKindOfClass:self])
        return parameters;
	
    else if ([parameters isKindOfClass:[NSArray class]]) {

        NSMutableArray *resources = [NSMutableArray arrayWithCapacity:[parameters count]];
        for (id item in parameters){
			
			
			[resources addObject:[self build:item withOptions:options]];
		}
            
        return resources;
    }
    
    else if ([parameters isKindOfClass:[NSDictionary class]]) {
						
        id resourceId = [parameters objectForKey:[self remoteIDField]];
						
		if (resourceId != nil && [self exists:$I([resourceId intValue])]){
			
			NSManagedObjectContext *moc = [options objectForKey:@"moc"] ? [options objectForKey:@"moc"] : [self managedObjectContext];
			resource = [self findByID:$I([resourceId intValue]) moc:moc];

			[resource update:parameters withOptions:options];
		}
		else
			resource = [self create:parameters withOptions:options];
    }
		
	return resource;
}

- (id) update:(NSDictionary *)data{
	
	return [self update:data withOptions:[[self class] defaultUpdateOptions]];
}

- (id) update:(NSDictionary *) data withOptions:(NSDictionary *) options{
		
	NSMutableDictionary *dict	= [NSMutableDictionary dictionary];
	NSDictionary *map			= [self map];
		
	for(NSString *key in [data keyEnumerator]){

		NSString *mappedKey = [[map allKeys] indexOfObject:key] == NSNotFound ? key : [map objectForKey:key];
		[dict setObject:[data objectForKey:key] forKey:[mappedKey stringByReplacingOccurrencesOfString:@"-" withString:@"_"]];
	}
		
	[self willUpdate:options];
			
    for (NSString *field in [dict allKeys]) {
		
        NSString *localField = nil;
        if ([field isEqualToString:[[self class] remoteIDField]])
            localField = [[self class] localIDField];
        else
            localField = [[self class] localNameForRemoteField:field];
        
        NSPropertyDescription *propertyDescription = [[self class] propertyDescriptionForField:localField inModel:[self class]];

        if (propertyDescription != nil) {
            id value = [dict objectForKey:field];
            
            // If property is a relationship, do some cascading object creation/updation
            if ([propertyDescription isKindOfClass:[NSRelationshipDescription class]]) {
				
                // Get relationship class from core data info
                NSRelationshipDescription *relationshipDescription = (NSRelationshipDescription *)propertyDescription;
                Class relationshipClass = NSClassFromString([[relationshipDescription destinationEntity] managedObjectClassName]);
                id newRelatedResources;
                id existingRelatedResources = [self valueForKey:localField];
								
                // ===== Get related resources from value ===== //
				NSDictionary *relationshipOptions = [options objectForKey:relationshipClass];
				
                // If the value is a dictionary or array, use it to create or update an resource                
                if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                    newRelatedResources = [relationshipClass build:value withOptions:options];
                    if ([newRelatedResources isKindOfClass:[NSArray class]])
                        newRelatedResources = [NSMutableSet setWithArray:newRelatedResources];
                }
                
                // Otherwise, if the value is a resource itself, use it directly
                else if ([value isKindOfClass:relationshipClass])
                    newRelatedResources = value;
				
                // ===== Apply related resources to self ===== //
                
                NSString *rule = [relationshipOptions objectForKey:@"rule"] ? [relationshipOptions objectForKey:@"rule"] : @"destroy";
                
                // To-many relationships
                if ([relationshipDescription isToMany]) {
                    
                    // If rule is to add, append new objects to existing
                    if ([rule isEqualToString:@"append"])
                        newRelatedResources = [existingRelatedResources setByAddingObjectsFromSet:newRelatedResources];
					
                    // If relationship rule is destroy, destroy all old resources that aren't in the new set
                    else if ([rule isEqualToString:@"destroy"]) {
                        NSSet *danglers = [existingRelatedResources difference:newRelatedResources];
                        for (id dangler in danglers)
                            [dangler remove];
                    }
                    
                    // Default action is to replace the set with no further reprecussions (old resources will still persist)
                    [self setValue:newRelatedResources forKey:localField];
                }
                
                // Singular relationships
                else {
                    // Only process if the new value is different from the current value
                    if (![newRelatedResources isEqual:existingRelatedResources]) {
                        
                        // Set new value
                        [self setValue:newRelatedResources forKey:localField];
                        
                        // If relationship rule is destroy, get rid of the old resource
                        if ([rule isEqualToString:@"destroy"])
                            [existingRelatedResources remove];
                    }
                }
            }
			
            else if ([propertyDescription isKindOfClass:[NSAttributeDescription class]]) {  
				                                
                if ([value isEqual:[NSNull null]])
                    [self setValue:nil forKey:localField];
				
                else {
                    switch ([(NSAttributeDescription *)propertyDescription attributeType]) {
							
                        case NSDateAttributeType:
							
                            if ([value isKindOfClass:[NSString class]]){
								
								NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
								[formatter setDateFormat:[[self class] dateFormat]];

								[self setValue:[formatter dateFromString:[self dateFormatPreprocessor:value]] forKey:localField];
								[formatter release];
							}
								
                            break;
							
						case NSInteger16AttributeType:
						case NSInteger32AttributeType:
						case NSInteger64AttributeType:
							[self setValue:$I([value intValue]) forKey:localField];
							break;
						
						case NSFloatAttributeType:
						case NSDecimalAttributeType:
							[self setValue:$F([value floatValue]) forKey:localField];
							break;
						
						case NSDoubleAttributeType:
							[self setValue:[NSNumber numberWithDouble:[value doubleValue]] forKey:localField];
							break;
						
						case NSBooleanAttributeType:
							[self setValue:[NSNumber numberWithBool:[value boolValue]] forKey:localField];
							break;
						case NSStringAttributeType:
							[self setValue:value forKey:localField];
							break;
                    }
                    
                }
            }
        }
    }
	
	[self didUpdate:options];

	return self;
}

+ (id) update:(NSDictionary *)data predicate:(NSPredicate *)predicate{
	
	ActiveResult *results = [self find:predicate];
	
	for(id row in [results objects]){
	
		[row update:data];
	}
	
	return self;
}

- (BOOL) shouldUpdateWith:(NSDictionary *)dict {
	
    SEL updatedAtSel = NSSelectorFromString([[self class] updatedAtField]);
	
    if ([self respondsToSelector:updatedAtSel]) {
		
        NSDate *updatedAt = (NSDate *)[self performSelector:updatedAtSel];
		
        if (updatedAt != nil) {
			
            NSString *dictUpdatedAtString = [dict objectForKey:[[self class] updatedAtField]];
			
            if (dictUpdatedAtString != nil) {
				
                NSDate *dictUpdatedAt = [[[self class] activeManager].defaultDateParser dateFromString:[self dateFormatPreprocessor:dictUpdatedAtString]];

                if (updatedAt != nil) {
                    return [updatedAt compare:dictUpdatedAt] == NSOrderedAscending;
                }
            }
        }
    }
	
    return YES;
}

#pragma mark -
#pragma mark Remove

+ (void) removeAll{

	[self remove:nil];
	[self save];
}

+ (void) remove:(NSPredicate *) predicate{
	
	ActiveResult *results = [self find:predicate];
	
	for(id row in [results objects]){
		
		[row remove];
	}
}

- (void) remove{
	
	[[self managedObjectContext] deleteObject:self];
}




#pragma mark -
#pragma mark Remote

+ (NSString *) remoteURLForAction:(Action)action{
	
	return $S(@"%@.%@", [[[[self entityName] lowercaseString] underscore] pluralForm], [self activeManager].remoteContentFormat);
}

- (NSString *) resourceURLForAction:(Action)action{
	
	NSMutableArray *pieces = [NSMutableArray arrayWithObject:[[$S(@"%@", [self class]) pluralForm] lowercaseString]];
	
	if(![self isInserted])
		[pieces addObject:$S(@"%i", [[self valueForKey:[[self class] localIDField]] intValue])];
	
	NSMutableString *name = [NSMutableString stringWithString:[pieces objectAtIndex:0]];
	
	if(![[self class] shouldParseEntityNameFromRelationships] || ![[self class] hasRelationships])
		return [pieces componentsJoinedByString:@"/"];
		
	for(NSString *key in [[self class] relationshipsByName]){
		
		NSRange search = [[pieces objectAtIndex:0] rangeOfString:key options:NSCaseInsensitiveSearch];
		
		if(search.location != NSNotFound){
			
			[pieces insertObject:[[key pluralForm] lowercaseString] atIndex:0];
			
			[name deleteCharactersInRange:search];			
			[pieces replaceObjectAtIndex:1 withObject:name];
			
			ActiveRecord *relationship = (ActiveRecord *) [self valueForKey:key];
			NSString *relatedId = [[relationship valueForKey:[[relationship class] localIDField]] stringValue];
			
			if(relatedId)
				[pieces insertObject:relatedId atIndex:1];
		}
	}
		
	return $S(@"%@.%@", [pieces componentsJoinedByString:@"/"], [[self class] activeManager].remoteContentFormat);
}

- (NSString *) relationshipURL:(NSString *) relationship forAction:(Action) action{
	
	return $S(@"%@/%i/%@.%@", [[[[[self class] entityName] lowercaseString] underscore] pluralForm], [[self valueForKey:[[self class] localIDField]] intValue], relationship, [[self class] activeManager].remoteContentFormat);
}

- (ActiveResult *) fetch{
	
	ActiveRequest *request = [self requestForFetch];

	return [[[self class] activeManager] addSyncronousRequest:request];	
}

- (void) fetchProperties:(NSDictionary *) properties{
	
	ActiveRequest *request = [self requestForFetch];
	[request addParameters:properties];
	
	[[[self class] activeManager] addRequest:request didParseObjectBlock:nil didFinishBlock:nil didFailBlock:nil];
}

- (void) fetch:(id) delegate didFinishSelector:(SEL) didFinishSelector didFailSelector:(SEL)didFailSelector{
	
	[self fetchRelationship:nil delegate:delegate didFinishSelector:didFinishSelector didFailSelector:didFailSelector];
}


- (void) fetch:(void(^)(ActiveResult *result))didFinishBlock didFailBlock:(void(^)(ActiveResult *result))didFailBlock{
	
	[self fetchRelationship:nil didFinishBlock:didFinishBlock didFailBlock:didFailBlock];
}

- (void) fetchRelationship:(NSString *) relationship delegate:(id) delegate didFinishSelector:(SEL) didFinishSelector didFailSelector:(SEL)didFailSelector{
	
	ActiveRequest *request = [self requestForFetch];
	
	if(relationship)
		request.urlPath = [self relationshipURL:relationship forAction:Read];
	
	
	request.didFinishSelector = didFinishSelector;
	request.didFailSelector = didFailSelector;
	
	[[[self class] activeManager] addRequest:request];
}

- (void) fetchRelationship:(NSString *) relationship didFinishBlock:(void(^)(ActiveResult *result))didFinishBlock didFailBlock:(void(^)(ActiveResult *result))didFailBlock{
	
	ActiveRequest *request = [self requestForFetch];
	
	if(relationship)
		request.urlPath = [self relationshipURL:relationship forAction:Read];
		
	[[[self class] activeManager] addRequest:request didParseObjectBlock:nil didFinishBlock:didFinishBlock didFailBlock:didFailBlock];
}

- (ActiveRequest *) requestForFetch{
	
	ActiveRequest *request = [ActiveRequest requestWithURLPath:[self resourceURLForAction:Read]];
	request.httpMethod = @"GET";
	request.delegate = self;
	
	return request;
}

- (void) push{

	ActiveRequest *request = [self requestForPush];
	request.didFinishSelector = _remoteDidFinishSelector;
	request.didFailSelector = _remoteDidFailSelector;
	request.delegate = _delegate;
	
	[[[self class] activeManager] addRequest:request];
}


- (void) push:(id) delegate didFinishSelector:(SEL) didFinishSelector didFailSelector:(SEL)didFailSelector{
	
	ActiveRequest *request = [self requestForPush];
	request.didFinishSelector = didFinishSelector;
	request.didFailSelector = didFailSelector;
	request.delegate = delegate;
	
	[[[self class] activeManager] addRequest:request];
}


- (void) push:(void(^)(ActiveResult *result))didFinishBlock didFailBlock:(void(^)(ActiveResult *result))didFailBlock{
	
	ActiveRequest *request = [self requestForPush];
	
	[[[self class] activeManager] addRequest:request didParseObjectBlock:nil didFinishBlock:didFinishBlock didFailBlock:didFailBlock];
}

- (ActiveRequest *) requestForPush{
	
	Action action = [self isInserted] ? Create : Update;
	
	ActiveRequest *request = [ActiveRequest requestWithURLPath:[self resourceURLForAction:action]];
	[request setDelegate:_delegate];
	[request setDidFinishSelector:_remoteDidFinishSelector];
	[request setDidFailSelector:_remoteDidFailSelector];
	[request setHttpMethod:@"POST"];
	
	if([self isUpdated])
		[request setHttpMethod:@"PUT"];
	else if([self isDeleted])
		[request setHttpMethod:@"DELETE"];
	
	if(![self isDeleted]){
		
		NSDictionary *properties = [self properties:$D([NSNumber numberWithBool:YES], @"$serializeDates", [NSNumber numberWithBool:NO], @"$relationships")];
		
		NSDictionary *post = [[self class] usesRootNode] ? $D(properties, [[self class] rootNodeName]) : properties;
		
		[request setHttpBody:[[[self class] activeManager] serializeObject:post]];
	}
	
	if(![self isInserted])
		[self save];
		
	return request;
}


+ (void) pull{
	
	ActiveRequest *request = [self requestForPull];
	
	[[self activeManager] addRequest:request];
}

+ (void) pull:(id) delegate didParseObjectSelector:(SEL)didParseObjectSelector didFinishSelector:(SEL) didFinishSelector didFailSelector:(SEL)didFailSelector{
	
	ActiveRequest *request = [self requestForPull];
	request.didFinishSelector = didFinishSelector;
	request.didFailSelector = didFailSelector;
	request.didParseObjectSelector = didParseObjectSelector;
	request.delegate = delegate;
	
	[[[self class] activeManager] addRequest:request];
}


+ (void) pull:(void(^)(id object))didParseObjectBlock didFinishBlock:(void(^)(ActiveResult *result))didFinishBlock didFailBlock:(void(^)(ActiveResult *result))didFailBlock{
	
	ActiveRequest *request = [self requestForPull];
	
	[[[self class] activeManager] addRequest:request didParseObjectBlock:didParseObjectBlock didFinishBlock:didFinishBlock didFailBlock:didFailBlock];
	
	[self save];
}

+ (ActiveRequest *) requestForPull{
	
	ActiveRequest *request = [ActiveRequest requestWithURLPath:[self remoteURLForAction:Read]];
	[request setDelegate:[self class]];
	[request setHttpMethod:@"GET"];
	[request setBatch:YES];
		
	return request;
}

- (NSString *) relationshipForURLPath:(NSString *) urlPath{
	
	NSString *url = [urlPath stringByReplacingOccurrencesOfString:$S(@".%@", [[[self class] activeManager] remoteContentFormat]) withString:@""];
	NSArray *divider = [url componentsSeparatedByString:@"?"];
	NSArray *pieces = [[divider objectAtIndex:0] componentsSeparatedByString:@"/"];
	[pieces makeObjectsPerformSelector:@selector(lowercaseString)];
	
	for(NSString *relationship in [[self class] relationshipsByName]){
		if([pieces containsObject:[relationship lowercaseString]])
			return [relationship lowercaseString];		
	}
	
	return nil;
}

- (Class) classForRelationship:(NSString *) relationship{
	
	
	NSRelationshipDescription *desc = [[[self class] relationshipsByName] objectForKey:relationship];
	return NSClassFromString([[desc destinationEntity] name]);
}


#pragma mark -
#pragma mark Remote Delegate

+ (void) connectionDidFinish:(ActiveResult *) result{

	if([result count] > 0){
	
		for(id object in result)
			[self build:object];
		
		[self save];
	}
}

+ (void) connectionDidFail:(ActiveResult *) result{
	
	NSLog(@"Connection Failed: %@", [result error]);
}

- (void) connectionDidFinish:(ActiveResult *) result{
			
	NSString *relationship = [self relationshipForURLPath:result.urlPath];
		
	if(relationship){

		NSRelationshipDescription *destEntity = [[[self class] relationshipsByName] objectForKey:relationship];
		NSArray *propertyNames = [[[destEntity destinationEntity] propertiesByName] allKeys];

		if(![propertyNames containsObject:[[self class] localIDField]])
			[self performSelector:NSSelectorFromString($S(@"remove%@:", [relationship capitalizedString])) withObject:[self valueForKey:relationship]];			
		
		Class relatedClass = [self classForRelationship:relationship];

		NSMutableSet *objects = [NSMutableSet setWithCapacity:[result count]];
		
		for(id object in result.objects){
			ActiveRecord *builtObject = [relatedClass build:object];
						
			if(builtObject)
				[objects addObject:builtObject];
		}

		[self performSelector:NSSelectorFromString($S(@"add%@:", [relationship capitalizedString])) withObject:objects];
	}else{

		[self update:[result object]];
	}
	
	[self save];
}

- (void) connectionDidFail:(ActiveResult *) result{
	
	[[self class] connectionDidFail:result];
}






#pragma mark -
#pragma mark Settings


+ (NSString *) localIDField{
	
	return @"id";
}

+ (NSString *) remoteIDField{
	
	return @"id";
}

+ (NSString *) defaultSort{
	
	return @"id DESC";
}

+ (NSString *) createdAtField{
	
	return @"created_at";
}

+ (NSString *) updatedAtField{
	
	return @"updated_at";
}

+ (NSString *) dateFormat{

	return @"yyyy-MM-dd'T'HH:mm:ssZZZ";
}

- (NSString *) dateFormatPreprocessor:(NSString *) date{
	
	return date;
}

+ (BOOL) remoteEnabled{
	
	return YES;
}

+ (NSString *) rootNodeName{
	
	return [[self entityName] lowercaseString];
}

- (void) didCreate:(id) parameters {}

- (void) willCreate:(id) parameters{}

- (void) didUpdate:(id) parameters {}

- (void) willUpdate:(id) parameters{}

+ (NSDictionary *) defaultCreateOptions { return nil; }

+ (NSDictionary *) defaultCreateOrUpdateOptions { return [self defaultCreateOptions]; }

+ (NSDictionary *) defaultUpdateOptions { return nil; }

+ (BOOL) usesRootNode{ return YES; }

+ (BOOL) shouldParseEntityNameFromRelationships{ return YES; }


- (void) dealloc{
	
	[super dealloc];
}

@end


