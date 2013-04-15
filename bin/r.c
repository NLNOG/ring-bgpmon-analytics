
#include <stdio.h>
#include <string.h>
#include <regex.h>

extern void bgp_regex_free (regex_t *regex);
extern regex_t *bgp_regcomp (const char *str);
extern int bgp_regexec (regex_t *regex, const char *aspath);

int main (int argc, char *argv[])
{
  if (bgp_regexec(bgp_regcomp(argv[1]), argv[2])) {
	return -1;
  } else {
        return 0;
  }
}

regex_t * bgp_regcomp (const char *regstr)
{
  int i, j;
  int len;
  int magic = 0;
  char *magic_str;
  char magic_regexp[] = "(^|[,{}()_ ]|$)";
  int ret;
  regex_t *regex;

  len = strlen (regstr);
  for (i = 0; i < len; i++)
    if (regstr[i] == '_')
      magic++;

  magic_str = malloc(len + (14 * magic) + 1);
  
  for (i = 0, j = 0; i < len; i++)
    {
      if (regstr[i] == '_')
        {
          memcpy (magic_str + j, magic_regexp, strlen (magic_regexp));
          j += strlen (magic_regexp);
        }
      else
        magic_str[j++] = regstr[i];
    }
  magic_str[j] = '\0';

  regex = malloc(sizeof (regex_t));

  ret = regcomp (regex, magic_str, REG_EXTENDED|REG_NOSUB);

  if (ret != 0)
    {
      free(regex);
      printf("Can't compile regular expression\n");
      return -1;
    }

  free(magic_str);
  return regex;
}

int bgp_regexec (regex_t *regex, const char *aspath)
{
  return regexec (regex, aspath, 0, NULL, 0);
}

void bgp_regex_free (regex_t *regex)
{
  regfree (regex);
  free(regex);
}

