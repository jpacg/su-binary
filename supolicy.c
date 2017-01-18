/* 
 * This was derived from public domain works with updates to 
 * work with more modern SELinux libraries. 
 * 
 * It is released into the public domain.
 * 
 */

#include <getopt.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/sendfile.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <ctype.h>


#include <sepol/debug.h>
#include <sepol/policydb/policydb.h>
#include <sepol/policydb/expand.h>
#include <sepol/policydb/link.h>
#include <sepol/policydb/services.h>
#include <sepol/policydb/avrule_block.h>
#include <sepol/policydb/conditional.h>

#include "common.h"

static void usage() {
	fprintf(stderr,
	"supolicy v0.01 - Copyright (C) 2014-2017 - wmshua.com\n"
	"\n"
	"supolicy --live [policy statement...]\n"
	"    Patches current policy and reload it\n"
	"\n"
	"supolicy --file infile outfile [policystatement...]\n"
	"    Patches infile and writes it to outfile\n"
	"\n"
	"supolicy --save outfile\n"
	"    Save current policy to file\n"
	"\n"
	"supolicy --load [policy statement...]\n"
	"    Load policy from file\n"
	"\n"
	"policy statement:\n"
	"  allow source_type target_type class permission\n"
	"  allow { source_type1 source_type2 ... } { target_type1 target_type2 ... } class { permission1 permission2 ... }\n"
	"  deny source_type target_type class permission\n"
	"  deny { source_type1 source_type2 ... } { target_type1 target_type2 ... } class { permission1 permission2 ... }\n"
	"  type_trans source_type target_type class trans_type\n"
	"  type_trans { source_type1 source_type2 } { target_type1 target_type2 } class trans_type\n"
	"  permissive type\n"
	"  enforcing type\n"
	"  force type\n"
	"  attradd type attribute\n"
	"  attrdel type attribute\n");
	exit(0);
}

static void usage2() {
	fprintf(stderr,
	"supolicy v2.79 (ndk:armeabi-v7a) - Copyright (C) 2014-2016 - Chainfire\n"
	"\n"
	"supolicy --live [policystatement...]\n"
	"    Patches current policy and reloads it\n"
	"\n"
	"supolicy --file infile outfile [policystatement...]\n"
	"    Patches infile and writes it to outfile\n"
	"\n"
	"supolicy --permissive [context...]\n"
	"    Returns permissive state for context or current\n"
	"\n"
	"supolicy --save outfile\n"
	"    Save current policy to file\n"
	"\n"
	"supolicy --load infile\n"
	"    Load policy from file\n"
	"\n"
	"supolicy --dumpav [infile]\n"
	"    Dump access vectors\n");
	exit(0);
}


////////////////////////////////////////////////////
// Begin


void *cmalloc(size_t s) {
	void *t = malloc(s);
	if (t == NULL) {
		fprintf(stderr, "Out of memory\n");
		exit(1);
	}
	return t;
}

int get_attr(char *type, int value, policydb_t *policy) {
	type_datum_t *attr = hashtab_search(policy->p_types.table, type);
	if (!attr)
		exit(1);

	if (attr->flavor != TYPE_ATTRIB)
		exit(1);

	return !! ebitmap_get_bit(&policy->attr_type_map[attr->s.value-1], value-1);
	//return !! ebitmap_get_bit(&policy->type_attr_map[value-1], attr->s.value-1);
}

int get_attr_id(char *type, policydb_t *policy) {
	type_datum_t *attr = hashtab_search(policy->p_types.table, type);
	if (!attr)
		exit(1);

	if (attr->flavor != TYPE_ATTRIB)
		exit(1);

	return attr->s.value;
}

int set_attr(char *type, int value, policydb_t *policy) {
	type_datum_t *attr = hashtab_search(policy->p_types.table, type);
	if (!attr)
		exit(1);

	if (attr->flavor != TYPE_ATTRIB)
		exit(1);

	if(ebitmap_set_bit(&policy->type_attr_map[value-1], attr->s.value-1, 1))
		exit(1);
	if(ebitmap_set_bit(&policy->attr_type_map[attr->s.value-1], value-1, 1))
		exit(1);

	return 0;
}

void create_domain(char *d, policydb_t *policy) {
	symtab_datum_t *src = hashtab_search(policy->p_types.table, d);
	if(src)
		return;

	type_datum_t *typdatum = (type_datum_t *) malloc(sizeof(type_datum_t));
	type_datum_init(typdatum);
	typdatum->primary = 1;
	typdatum->flavor = TYPE_TYPE;

	uint32_t value = 0;
	int r = symtab_insert(policy, SYM_TYPES, strdup(d), typdatum, SCOPE_DECL, 1, &value);
	typdatum->s.value = value;

	// fprintf(stderr, "source type %s does not exist: %d,%d\n", d, r, value);
	if (ebitmap_set_bit(&policy->global->branch_list->declared.scope[SYM_TYPES], value - 1, 1)) {
		exit(1);
	}

	policy->type_attr_map = realloc(policy->type_attr_map, sizeof(ebitmap_t)*policy->p_types.nprim);
	policy->attr_type_map = realloc(policy->attr_type_map, sizeof(ebitmap_t)*policy->p_types.nprim);
	ebitmap_init(&policy->type_attr_map[value-1]);
	ebitmap_init(&policy->attr_type_map[value-1]);
	ebitmap_set_bit(&policy->type_attr_map[value-1], value-1, 1);

	//Add the domain to all roles
	for(unsigned i=0; i<policy->p_roles.nprim; ++i) {
		//Not sure all those three calls are needed
		ebitmap_set_bit(&policy->role_val_to_struct[i]->types.negset, value-1, 0);
		ebitmap_set_bit(&policy->role_val_to_struct[i]->types.types, value-1, 1);
		type_set_expand(&policy->role_val_to_struct[i]->types, &policy->role_val_to_struct[i]->cache, policy, 0);
	}


	src = hashtab_search(policy->p_types.table, d);
	if(!src)
		exit(1);

	extern int policydb_index_decls(policydb_t * p);
	if(policydb_index_decls(policy))
		exit(1);

	if(policydb_index_classes(policy))
		exit(1);

	if(policydb_index_others(NULL, policy, 1))
		exit(1);

	set_attr("domain", value, policy);
}

int add_irule(int s, int t, int c, int p, int effect, int not, policydb_t* policy) {
	avtab_datum_t *av;
	avtab_key_t key;

	key.source_type = s;
	key.target_type = t;
	key.target_class = c;
	key.specified = effect;
	av = avtab_search(&policy->te_avtab, &key);

	if (av == NULL) {
		av = cmalloc(sizeof(*av));
		av->data |= 1U << (p - 1);
		int ret = avtab_insert(&policy->te_avtab, &key, av);
		if (ret) {
			// fprintf(stderr, "Error inserting into avtab\n");
			return 1;
		}
	}

	if(not)
		av->data &= ~(1U << (p - 1));
	else
		av->data |= 1U << (p - 1);
	return 0;
}

int add_typerule(char *s, char *targetAttribute, char **minusses, char *c, char *p, int effect, int not, policydb_t *policy) {
	type_datum_t *src, *tgt;
	class_datum_t *cls;
	perm_datum_t *perm;

	//64(0kB) should be enough for everyone, right?
	int m[64] = { -1 };

	src = hashtab_search(policy->p_types.table, s);
	if (src == NULL) {
		// fprintf(stderr, "source type %s does not exist\n", s);
		return 1;
	}

	tgt = hashtab_search(policy->p_types.table, targetAttribute);
	if (tgt == NULL) {
		// fprintf(stderr, "target type %s does not exist\n", targetAttribute);
		return 1;
	}
	if(tgt->flavor != TYPE_ATTRIB)
		exit(1);

	for(int i=0; minusses && minusses[i]; ++i) {
		type_datum_t *obj;
		obj = hashtab_search(policy->p_types.table, minusses[i]);
		if (obj == NULL) {
			// fprintf(stderr, "minus type %s does not exist\n", minusses[i]);
			return 1;
		}
		m[i] = obj->s.value-1;
		m[i+1] = -1;
	}

	cls = hashtab_search(policy->p_classes.table, c);
	if (cls == NULL) {
		// fprintf(stderr, "class %s does not exist\n", c);
		return 1;
	}

	perm = hashtab_search(cls->permissions.table, p);
	if (perm == NULL) {
		if (cls->comdatum == NULL) {
			// fprintf(stderr, "perm %s does not exist in class %s\n", p, c);
			return 1;
		}
		perm = hashtab_search(cls->comdatum->permissions.table, p);
		if (perm == NULL) {
			// fprintf(stderr, "perm %s does not exist in class %s\n", p, c);
			return 1;
		}
	}

	ebitmap_node_t *node;
	int i;

	int ret = 0;

	ebitmap_for_each_bit(&policy->attr_type_map[tgt->s.value-1], node, i) {
		if(ebitmap_node_get_bit(node, i)) {
			int found = 0;
			for(int j=0; m[j] != -1; ++j) {
				if(i == m[j])
					found = 1;
			}

			if(!found)
				ret |= add_irule(src->s.value, i+1, cls->s.value, perm->s.value, effect, not, policy);
		}
	}
	return ret;
}

int add_transition(char *srcS, char *origS, char *c, char *tgtS, policydb_t *policy) {
	type_datum_t *src, *tgt, *orig;
	class_datum_t *cls;

	avtab_datum_t *av;
	avtab_key_t key;

	src = hashtab_search(policy->p_types.table, srcS);
	if (src == NULL) {
		// fprintf(stderr, "source type %s does not exist\n", srcS);
		return 1;
	}
	tgt = hashtab_search(policy->p_types.table, tgtS);
	if (tgt == NULL) {
		// fprintf(stderr, "target type %s does not exist\n", tgtS);
		return 1;
	}
	cls = hashtab_search(policy->p_classes.table, c);
	if (cls == NULL) {
		// fprintf(stderr, "class %s does not exist\n", c);
		return 1;
	}
	orig = hashtab_search(policy->p_types.table, origS);
	if (orig == NULL) {
		// fprintf(stderr, "class %s does not exist\n", origS);
		return 1;
	}

	key.source_type = src->s.value;
	key.target_type = orig->s.value;
	key.target_class = cls->s.value;
	key.specified = AVTAB_TRANSITION;
	av = avtab_search(&policy->te_avtab, &key);

	if (av == NULL) {
		av = cmalloc(sizeof(*av));
		av->data = tgt->s.value;
		int ret = avtab_insert(&policy->te_avtab, &key, av);
		if (ret) {
			// fprintf(stderr, "Error inserting into avtab\n");
			return 1;
		}
	} else {
		av->data = tgt->s.value;
		// fprintf(stderr, "Warning, rule already defined! Won't override.\n");
		// fprintf(stderr, "Previous value = %d, wanted value = %d\n", av->data, tgt->s.value);
	}

	return 0;
}

int add_file_transition(char *srcS, char *origS, char *tgtS, char *c, char* filename, policydb_t *policy) {
	type_datum_t *src, *tgt, *orig;
	class_datum_t *cls;

	src = hashtab_search(policy->p_types.table, srcS);
	if (src == NULL) {
		// fprintf(stderr, "source type %s does not exist\n", srcS);
		return 1;
	}
	tgt = hashtab_search(policy->p_types.table, tgtS);
	if (tgt == NULL) {
		// fprintf(stderr, "target type %s does not exist\n", tgtS);
		return 1;
	}
	cls = hashtab_search(policy->p_classes.table, c);
	if (cls == NULL) {
		// fprintf(stderr, "class %s does not exist\n", c);
		return 1;
	}
	orig = hashtab_search(policy->p_types.table, origS);
	if (cls == NULL) {
		// fprintf(stderr, "class %s does not exist\n", origS);
		return 1;
	}

	filename_trans_t *new_transition = cmalloc(sizeof(*new_transition));
	new_transition->stype = src->s.value;
	new_transition->ttype = orig->s.value;
	new_transition->tclass = cls->s.value;
	new_transition->otype = tgt->s.value;
	new_transition->name = strdup(filename);
	new_transition->next = policy->filename_trans;

	policy->filename_trans = new_transition;

	return 0;
}

int add_type(char *domainS, char *typeS, policydb_t *policy) {
	type_datum_t *domain;

	domain = hashtab_search(policy->p_types.table, domainS);
	if (domain == NULL) {
		// fprintf(stderr, "source type %s does not exist\n", domainS);
		return 1;
	}

	set_attr(typeS, domain->s.value, policy);

	int typeId = get_attr_id(typeS, policy);
	//Now let's update all constraints!
	//(kernel doesn't support (yet?) type_names rules)
	for(int i=0; i<policy->p_classes.nprim; ++i) {
		class_datum_t *cl = policy->class_val_to_struct[i];
		for(constraint_node_t *n = cl->constraints; n ; n=n->next) {
			for(constraint_expr_t *e = n->expr; e; e=e->next) {
				if(e->expr_type == CEXPR_NAMES) {
					if(ebitmap_get_bit(&e->type_names->types, typeId-1)) {
						ebitmap_set_bit(&e->names, domain->s.value-1, 1);
					}
				}
			}
		}
	}
	return 0;
}

int load_policy(char *filename, policydb_t *policydb, struct policy_file *pf) {
	int fd;
	struct stat sb;
	void *map;
	int ret;

	fd = open(filename, O_RDONLY);
	if (fd < 0) {
		fprintf(stderr, "Can't open '%s':  %s\n",
				filename, strerror(errno));
		return 1;
	}
	if (fstat(fd, &sb) < 0) {
		fprintf(stderr, "Can't stat '%s':  %s\n",
				filename, strerror(errno));
		return 1;
	}
	map = mmap(NULL, sb.st_size, PROT_READ | PROT_WRITE, MAP_PRIVATE,
				fd, 0);
	if (map == MAP_FAILED) {
		fprintf(stderr, "Can't mmap '%s':  %s\n",
				filename, strerror(errno));
		return 1;
	}

	policy_file_init(pf);
	pf->type = PF_USE_MEMORY;
	pf->data = map;
	pf->len = sb.st_size;
	if (policydb_init(policydb)) {
		fprintf(stderr, "policydb_init: Out of memory!\n");
		return 1;
	}
	ret = policydb_read(policydb, pf, 1);
	if (ret) {
		fprintf(stderr, "error(s) encountered while parsing configuration\n");
		return 1;
	}

	return 0;
}

int add_rule_auto(type_datum_t *src, type_datum_t *tgt, class_datum_t *cls, perm_datum_t *perm, int effect, int not, policydb_t *policy) {
	hashtab_t type_table, class_table, perm_table;
	hashtab_ptr_t cur;
	
	type_table = policy->p_types.table;
	class_table = policy->p_classes.table;

	if (src == NULL) {
		for (int i = 0; i < type_table->size; ++i) {
			cur = type_table->htable[i];
			while (cur != NULL) {
				src = cur->datum;
				if(add_rule_auto(src, tgt, cls, perm, effect, not, policy))
					return 1;
				cur = cur->next;
			}
		}
	} else if (tgt == NULL) {
		for (int i = 0; i < type_table->size; ++i) {
			cur = type_table->htable[i];
			while (cur != NULL) {
				tgt = cur->datum;
				if(add_rule_auto(src, tgt, cls, perm, effect, not, policy))
					return 1;
				cur = cur->next;
			}
		}
	} else if (cls == NULL) {
		for (int i = 0; i < class_table->size; ++i) {
			cur = class_table->htable[i];
			while (cur != NULL) {
				cls = cur->datum;
				if(add_rule_auto(src, tgt, cls, perm, effect, not, policy))
					return 1;
				cur = cur->next;
			}
		}
	} else if (perm == NULL) {
		perm_table = cls->permissions.table;
		for (int i = 0; i < perm_table->size; ++i) {
			cur = perm_table->htable[i];
			while (cur != NULL) {
				perm = cur->datum;
				if(add_irule(src->s.value, tgt->s.value, cls->s.value, perm->s.value, effect, not, policy))
					return 1;
				cur = cur->next;
			}
		}

		if (cls->comdatum != NULL) {
			perm_table = cls->comdatum->permissions.table;
			for (int i = 0; i < perm_table->size; ++i) {
				cur = perm_table->htable[i];
				while (cur != NULL) {
					perm = cur->datum;
					if(add_irule(src->s.value, tgt->s.value, cls->s.value, perm->s.value, effect, not, policy))
						return 1;
					cur = cur->next;
				}
			}
		}
	} else {
		return add_irule(src->s.value, tgt->s.value, cls->s.value, perm->s.value, effect, not, policy);
	}
	return 0;
}

int add_rule(char *s, char *t, char *c, char *p, int effect, int not, policydb_t *policy) {
	type_datum_t *src = NULL, *tgt = NULL;
	class_datum_t *cls = NULL;
	perm_datum_t *perm = NULL;

	if (s) {
		src = hashtab_search(policy->p_types.table, s);
		if (src == NULL) {
			// fprintf(stderr, "source type %s does not exist\n", s);
			return 1;
		}
	}

	if (t) {
		tgt = hashtab_search(policy->p_types.table, t);
		if (tgt == NULL) {
			// fprintf(stderr, "target type %s does not exist\n", t);
			return 1;
		}
	}

	if (c) {
		cls = hashtab_search(policy->p_classes.table, c);
		if (cls == NULL) {
			// fprintf(stderr, "class %s does not exist\n", c);
			return 1;
		}
	}

	if (p) {
		if (c == NULL) {
			// fprintf(stderr, "No class is specified, cannot add perm [%s] \n", p);
			return 1;
		}
		
		if (cls != NULL) {
			perm = hashtab_search(cls->permissions.table, p);
			if (perm == NULL && cls->comdatum != NULL) {
				perm = hashtab_search(cls->comdatum->permissions.table, p);
			}
			if (perm == NULL) {
				// fprintf(stderr, "perm %s does not exist in class %s\n", p, c);
				return 1;
			}
		}
	}
	return add_rule_auto(src, tgt, cls, perm, effect, not, policy);
}

int live_patch(policydb_t *policydb, char *filename) {
	//char *filename = "/sys/fs/selinux/load";
	int fd, ret;
	void *data = NULL;
	size_t len;

	policydb_to_image(NULL, policydb, &data, &len);
	if (data == NULL) fprintf(stderr, "Error!");

	// based on libselinux security_load_policy()
	fd = open(filename, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "Can't open '%s':  %s\n",
		        filename, strerror(errno));
		return 1;
	}
	ret = write(fd, data, len);
	close(fd);
	if (ret < 0) {
		fprintf(stderr, "Could not write policy to %s\n",
		        filename);
		return 1;
	}
	return 0;
}


// End
//////////////////////////////////////////////////////////

/*
void allow(char *s, char *t, char *c, char *p) {
	add_rule(s, t, c, p, AVTAB_ALLOWED, 0, policy);
}

void noaudit(char *s, char *t, char *c, char *p) {
	add_rule(s, t, c, p, AVTAB_AUDITDENY, 0, policy);
}

void deny(char *s, char *t, char *c, char *p) {
	add_rule(s, t, c, p, AVTAB_ALLOWED, 1, policy);
}

void setPermissive(char* permissive, int permissive_value) {
	type_datum_t *type;
	create_domain(permissive, policy);
	type = hashtab_search(policy->p_types.table, permissive);
	if (type == NULL) {
			fprintf(stderr, "type %s does not exist\n", permissive);
			return;
	}
	if (ebitmap_set_bit(&policy->permissive_map, type->s.value, permissive_value)) {
		fprintf(stderr, "Could not set bit in permissive map\n");
		return;
	}
}

int exists(char* source) {
	return (int) hashtab_search(policy->p_types.table, source);
}
*/
//////////////////////////////////////////////////////////



typedef struct {
	char s[100];
	char t[100];
	char c[100];
	type_datum_t *src;
	type_datum_t *tgt;
	class_datum_t *cls;
	policydb_t *policy;
}any_perm_add_rule_helper;

int apply_any_perm_add_rule(hashtab_key_t k, hashtab_datum_t d, void *args){
	any_perm_add_rule_helper *helper = args;
	// printf("-- allow : %s %s %s %s", helper->s, helper->t, helper->c, k);
	add_rule(helper->s, helper->t, helper->c, k, AVTAB_ALLOWED, 0, helper->policy);
	return 0;
}

int add_rules(char *s, char *t, char *c, char *p, policydb_t *policy) {
	if(strcmp(p, "*") == 0){
		type_datum_t *src, *tgt;
		class_datum_t *cls;
		src = hashtab_search(policy->p_types.table, s);
		if (src == NULL) {
			//LOGD("source type %s does not exist", s);
			return 1;
		}

		tgt = hashtab_search(policy->p_types.table, t);
		if (tgt == NULL) {
			//LOGD("target type %s does not exist", t);
			return 1;
		}

		cls = hashtab_search(policy->p_classes.table, c);
		if (cls == NULL) {
			//LOGD("class %s does not exist", c);
			return 1;
		}
		any_perm_add_rule_helper helper;
		strcpy(helper.s, s);
		strcpy(helper.t, t);
		strcpy(helper.c, c);
		helper.src = src;
		helper.tgt = tgt;
		helper.cls = cls;
		helper.policy = policy;
		hashtab_map(cls->permissions.table, apply_any_perm_add_rule ,&helper);

		if (cls->comdatum != NULL) {
            // printf("<<<<<<---------------------------- begin\n");
            hashtab_map(cls->comdatum->permissions.table, apply_any_perm_add_rule ,&helper);
            // printf("---------------------------->>>>>> end\n\n");
        }
	}
	else{
		add_rule(s, t, c, p, AVTAB_ALLOWED, 0, policy);
	}
	return 0;
}


















/////////////////////////////////////////////////////////////////////////////
// new


void my_set_permissive(policydb_t* policy, char* permissive, int permissive_value) {
	type_datum_t *type;
	// create_domain(permissive, policy);
	type = hashtab_search(policy->p_types.table, permissive);
	if (type == NULL) {
			// fprintf(stderr, "type %s does not exist\n", permissive);
			return;
	}
	if (ebitmap_set_bit(&policy->permissive_map, type->s.value, permissive_value)) {
		// fprintf(stderr, "Could not set bit in permissive map\n");
		return;
	}
}

int my_add_rules_auto(char *source, char *target, char *class, char *perm, policydb_t *policydb) {
	char *source_token = NULL;
	char *source_saveptr = NULL;
	char *target_token = NULL;
	char *target_saveptr = NULL;
	char *perm_token = NULL;
	char *perm_saveptr=NULL;

	source = strdup(source);
	target = strdup(target);
	perm = strdup(perm);

	source_token = strtok_r(source, " ", &source_saveptr);
	while(source_token){
		target_token = strtok_r(target, " ", &target_saveptr);
		while(target_token){
			perm_token = strtok_r(perm, " ", &perm_saveptr);
			while (perm_token) {
				// printf("-- add rule : %s %s %s %s\n", source_token, target_token, class, perm_token);
				if (add_rules(source_token, target_token, class, perm_token, policydb)) {
				}
				perm_token = strtok_r(NULL, " ", &perm_saveptr);
			}
			target_token = strtok_r(NULL, " ", &target_saveptr);
		}
		source_token = strtok_r(NULL, " ", &source_saveptr);
	}


	free(source);
	free(target);
	free(perm);

	return 0;
}


int patch_sepolicy(char *filename, char *patch_save_path)
{
	char *policy = NULL;

	policydb_t policydb;
	sidtab_t sidtab;
	struct policy_file pf;
	policy  = filename;
	if (!policy)
		policy = "/sys/fs/selinux/policy";

	sepol_set_policydb(&policydb);
	sepol_set_sidtab(&sidtab);

	if (load_policy(policy, &policydb, &pf)) {
		PLOGE("Could not load policy ");
		return -1;
	}

	if (policydb_load_isids(&policydb, &sidtab))
		return -1;

	/**
	 * Patch begin
	 */

	/**
	 * permissive init
	 * permissive init_shell
	 * permissive kernel
	 * permissive toolbox
	 * permissive recovery
	 * permissive zygote
	 * permissive servicemanager
	 * permissive system_server
	 * permissive s_init_shell
	 * permissive toolbox_exec
	 * permissive su
	 * permissive undefined_service
	 * permissive qti_init_shell
	 * permissive sudaemon
	 */
	my_set_permissive(&policydb, "init", 1);
	my_set_permissive(&policydb, "init_shell", 1);
	my_set_permissive(&policydb, "kernel", 1);
	my_set_permissive(&policydb, "toolbox", 1);
	my_set_permissive(&policydb, "recovery", 1);
	my_set_permissive(&policydb, "zygote", 1);
	my_set_permissive(&policydb, "servicemanager", 1);
	my_set_permissive(&policydb, "system_server", 1);
	my_set_permissive(&policydb, "s_init_shell", 1);
	my_set_permissive(&policydb, "toolbox_exec", 1);
	my_set_permissive(&policydb, "su", 1);
	my_set_permissive(&policydb, "undefined_service", 1);
	my_set_permissive(&policydb, "qti_init_shell", 1);
	my_set_permissive(&policydb, "sudaemon", 1);


	/**
	 * force init
	 * force init_shell
	 * force kernel
	 * force toolbox
	 * force recovery
	 * force zygote
	 * force servicemanager
	 * force system_server
	 * force s_init_shell
	 * force toolbox_exec
	 * force su
	 * force undefined_service
	 * force qti_init_shell
	 * force sudaemon
	 */

	// king_force




	/**
	 * allow { init init_shell kernel toolbox recovery s_init_shell su undefined_service qti_init_shell debuggerd } kernel security *
	 * allow domain init socket *
	 * allow { shell system_server system appdomain zygote recovery } system_file file { entrypoint }
	 * allow domain init unix_stream_socket *
	 * allow appdomain device sock_file *
	 * allow installd { system_file system } file { unlink }
	 * allow { system system_server } init process noatsecure
	 */
	my_add_rules_auto("init init_shell kernel toolbox recovery s_init_shell su undefined_service qti_init_shell debuggerd", "kernel", "security", "*", &policydb);
	my_add_rules_auto("domain", "init", "socket", "*", &policydb);
	my_add_rules_auto("shell system_server system appdomain zygote recovery", "system_file", "file", "entrypoint", &policydb);
	my_add_rules_auto("domain", "init", "unix_stream_socket", "*", &policydb);
	my_add_rules_auto("appdomain", "device", "sock_file", "*", &policydb);
	my_add_rules_auto("installd", "system_file system", "file", "unlink", &policydb);
	my_add_rules_auto("system system_server", "init", "process", "noatsecure", &policydb);


	/**
	 * type_trans init { shell_exec toolbox_exec } process init
	 * type_trans kernel init_exec process init
	 * type_trans undefined_service shell_exec process init
	 */
	add_transition("init", "shell_exec", "process", "init", &policydb);
	add_transition("init", "toolbox_exec", "process", "init", &policydb);
	add_transition("kernel", "init_exec", "process", "init", &policydb);
	add_transition("undefined_service", "shell_exec", "process", "init", &policydb);

	/**
	 * Patch end
	 */

	if (live_patch(&policydb, patch_save_path)) {
		PLOGE("Could not load new policy into kernel ");
		return 1;
	}

	policydb_destroy(&policydb);

	return 0;
}



int supolicy_main(int argc, char *argv[], char *envp[]) {
	if (argc < 2) {
		usage();
	}

	if (strcmp(argv[1], "--live") == 0 ) {
		if (patch_sepolicy("/sys/fs/selinux/policy", "/sys/fs/selinux/load") == 0) {
			printf("Success\n");
		}
		else {
			printf("Failure\n");
		}
	}
	else if (strcmp(argv[1], "--file") == 0) {
		if (patch_sepolicy(argv[2], argv[3]) == 0) {
			printf("Success\n");
		}
		else {
			printf("Failure\n");
		}
	}

	return 0;
}
